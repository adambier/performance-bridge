// sbdev arturia: a prototype that shows a standalone Arturia instrument on the Roto-Control's
// PLUGIN mode (docs/PLUGIN-MODE-PLAN.md, section 6). sbdev opens the device and runs the
// handshake as type 02, publishes a virtual port under a first KeyLab keyboard's name for the
// instrument, and runs the ArturiaRotoDriver library between the two. Nothing here has been
// tested on the device or with an instrument.

import Foundation
import RotoControl
import ArturiaControl
import ArturiaRotoDriver
import MIDITransport

let arturiaUsage = """
    Usage: sbdev arturia [--port NAME] [--wait] [--device NAME | --in NAME --out NAME] [--gap MS]
        Connects to the Roto-Control, runs the handshake as type 02, and publishes a virtual
        MIDI source and destination named NAME (--port; default "KeyLab 61"), the name of a
        controller an Arturia instrument reports its values to. In PLUGIN mode the
        Roto-Control is then offered one macro plugin with two pages:
          page 1   knobs 1–4: Macro 1–4;  knobs 5–8: four parameters of the instrument's own,
                   shown as Param 1–4 (their real names are not known to this tool)
          page 2   knob 1: Volume
        In MIX mode sbdev shows a page of stand-in tracks, as `sbdev relay` does.
        This is a prototype for a test. Whether it works is what the test is to find out.

        To try it:
          1. Quit Performance Bridge and every other sbdev tool.
          2. Start `sbdev arturia`, then the instrument.
          3. In the instrument's audio and MIDI settings window, turn on the port under MIDI
             Devices (the window's labels have not been recorded).
          4. Press MODE, then PLUGIN, on the Roto-Control.
        A control's name ends in "?" until the instrument reports its value. To make it
        report, move the control in the instrument's window, or load a preset.

        --wait sends LEARN PARAM only in answer to CONTROL MAPPED, which is the order of
        Melbourne Instruments' Bitwig integration; try it first. Without --wait, LEARN PARAM
        is sent unasked, which is this project's own variant. (Use whichever of
        `sbdev roto`'s `macro --wait` and `macro` test R1 found to work.)

        --device matches the Roto-Control's source and destination by name (default "Roto");
        --in and --out name them separately. --gap is the pause after each SysEx message sent
        to the Roto-Control (default 5 ms).

        Each line has the time since starting, the direction, the bytes, and what they mean:
          instrument → sbdev, sbdev → instrument   the virtual port
          device → sbdev, sbdev → device           the Roto-Control (PLUGIN mode's driver)
          local → device                           sbdev's handshake and MIX-mode page

    """ + arturiaCommandHelp

let arturiaCommandHelp = """
      status        prints the mode, the page, the plugin's name, and each control's value
      mark <text>   prints a line with the time and the text
      help          this list
      quit          removes the virtual ports and exits
    """

struct ArturiaOptions {
    var inName = "Roto"
    var outName = "Roto"
    var portName = "KeyLab 61"
    var wait = false
    var gapMilliseconds = 5
}

func parseArturiaOptions(_ arguments: ArraySlice<String>) -> ArturiaOptions {
    var options = ArturiaOptions()
    var rest = arguments
    func value(_ option: String) -> String {
        guard let text = rest.popFirst() else { fail("\(option) needs a value.\n\n\(arturiaUsage)") }
        return text
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "--port": options.portName = value(argument)
        case "--wait": options.wait = true
        case "--device": let name = value(argument); options.inName = name; options.outName = name
        case "--in": options.inName = value(argument)
        case "--out": options.outName = value(argument)
        case "--gap":
            guard let gap = Int(value(argument)), gap >= 0 else { fail("--gap needs a number of milliseconds.") }
            options.gapMilliseconds = gap
        case "-h", "--help": print(arturiaUsage); exit(0)
        default: fail("Unknown option \(argument).\n\n\(arturiaUsage)")
        }
    }
    return options
}

/// One line of the log: the direction in a fixed column, the bytes, and what they mean.
func arturiaLine(_ direction: String, _ bytes: [UInt8], _ words: String) -> String {
    direction + String(repeating: " ", count: max(19 - direction.count, 1)) + hex(bytes) + "   [\(words)]"
}

/// Whether a message from the Roto-Control goes to the stand-in owner of MIX mode
/// (`RelayLocalOwner`): the handshake's and the versions' always, and everything else only while
/// the device is not in PLUGIN mode.
func arturiaIsForLocalOwner(_ message: RotoIncoming, inPluginMode: Bool) -> Bool {
    switch message {
    case .pingDAW, .connected, .firmwareVersion, .sysExAPIVersion: return true
    case .pluginMode: return false
    default: return !inPluginMode
    }
}

/// The driver with its two connections. One lock guards everything, since the device's bytes, the
/// instrument's bytes, the clock, and the keyboard's commands arrive on four threads.
final class ArturiaSession: @unchecked Sendable {
    private let options: ArturiaOptions
    private let lock = NSLock()
    private let start = Date()
    private var driver: ArturiaRotoDriver
    private var local = RelayLocalOwner()
    private var parser = RotoMIDIParser()
    private var controls = RotoControlDecoder()
    private var assembler = ArturiaSysExAssembler()
    private var device: MIDIConnection?
    private var port: VirtualMIDIPort?

    init(options: ArturiaOptions) {
        self.options = options
        driver = ArturiaRotoDriver(waitsForControlMapped: options.wait)
    }

    func connect() {
        // Held until the handshake has started, so that input arriving meanwhile waits.
        lock.lock()
        defer { lock.unlock() }
        do {
            port = try VirtualMIDIPort(clientName: "sbdev arturia", name: options.portName) { [weak self] bytes in
                self?.fromInstrument(bytes)
            }
            device = try MIDIConnection(clientName: "sbdev arturia", sourceName: options.inName, destinationName: options.outName) { [weak self] bytes in
                self?.fromDevice(bytes)
            }
        } catch {
            fail("\(error)")
        }
        log("Published a MIDI source and a MIDI destination named \"\(options.portName)\".")
        log("Listening to \"\(device!.source.name)\", sending to \"\(device!.destination.name)\". Type `help` for commands.")
        sendLocal(local.handshake.start())
    }

    /// Calls the driver's `tick` every 20 ms, on a thread of its own, until the program exits.
    func startClock() {
        let thread = Thread { [weak self] in
            while let session = self {
                session.tick()
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        thread.start()
    }

    private func now(_ time: Date = Date()) -> TimeInterval { time.timeIntervalSince(start) }

    /// Prints a line with the time since starting (or since `at`). Called with the lock held.
    private func log(_ text: String, at time: Date = Date()) {
        print(String(format: "%9.3f  ", now(time)) + text)
        flushOutput()
    }

    private func tick() {
        lock.lock()
        defer { lock.unlock() }
        carryOut(driver.tick(now: now()))
    }

    private func fromInstrument(_ bytes: [UInt8]) {
        let arrived = Date()
        lock.lock()
        defer { lock.unlock() }
        log(arturiaLine("instrument → sbdev", bytes, "received"), at: arrived)
        for message in assembler.feed(bytes) {
            if let parsed = ArturiaInstrumentMessage.parse(message), let words = vportDescribe(parsed) {
                log("   " + words, at: arrived)
            }
        }
        carryOut(driver.fromInstrument(bytes, now: now(arrived)))
    }

    private func fromDevice(_ bytes: [UInt8]) {
        let arrived = Date()
        lock.lock()
        defer { lock.unlock() }
        for message in parser.feed(bytes) {
            switch message {
            case .sysEx(let sysEx):
                guard let incoming = RotoIncoming(sysEx: sysEx) else {
                    log(arturiaLine("device → sbdev", sysEx, "not a Roto-Control message"), at: arrived); continue
                }
                log(arturiaLine("device → sbdev", sysEx, describe(incoming)), at: arrived)
                let wasInPluginMode = driver.isInPluginMode
                carryOut(driver.fromDevice(.message(incoming), now: now(arrived)))
                if wasInPluginMode != driver.isInPluginMode { log("   " + (driver.isInPluginMode ? "now in PLUGIN mode" : "now in MIX mode")) }
                if arturiaIsForLocalOwner(incoming, inPluginMode: driver.isInPluginMode) {
                    sendLocal(local.react(to: incoming))
                }
            case .controlChange(let channel, let controller, let value):
                let cc: [UInt8] = [0xB0 | channel, controller, value]
                guard let event = controls.decode(channel: channel, controller: controller, value: value) else {
                    log(arturiaLine("device → sbdev", cc, "a knob's high 7 bits"), at: arrived); continue
                }
                log(arturiaLine("device → sbdev", cc, describe(event)), at: arrived)
                carryOut(driver.fromDevice(.control(event), now: now(arrived)))
            case .other(let other):
                log(arturiaLine("device → sbdev", other, "not a control change or SysEx"), at: arrived)
            }
        }
    }

    /// Prints and sends what the driver returned. Called with the lock held.
    private func carryOut(_ output: ArturiaRotoOutput) {
        for message in output.toInstrument {
            log(arturiaLine("sbdev → instrument", message, "control change \(message.count > 2 ? "\(message[1]) = \(message[2])" : "")"))
            guard let port else { log("   not sent: no virtual port"); continue }
            do { try port.send(message) } catch { log("   could not send to the instrument: \(error)") }
        }
        for message in output.toDevice {
            let words: String
            switch message {
            case .message(let outgoing): words = describe(outgoing)
            case .knob(let knob, let position): words = "knob \(knob + 1) to \(position)"
            }
            log(arturiaLine("sbdev → device", message.bytes, words))
            sendToDevice(message.bytes)
        }
    }

    /// Sends the stand-in MIX owner's messages to the device, printing each. Called with the lock held.
    private func sendLocal(_ messages: [RotoOutgoing]) {
        for message in messages {
            log(arturiaLine("local → device", message.bytes, describe(message)))
            sendToDevice(message.bytes)
        }
    }

    private func sendToDevice(_ bytes: [UInt8]) {
        guard let device else { log("   not sent: no connection"); return }
        do {
            try device.send(bytes)
        } catch {
            log("   could not send to the device: \(error)")
        }
        if bytes.first == 0xF0, options.gapMilliseconds > 0 {
            Thread.sleep(forTimeInterval: Double(options.gapMilliseconds) / 1000)
        }
    }

    private func printStatus() {
        log("\(driver.isInPluginMode ? "PLUGIN" : "MIX") mode, page \(driver.page + 1), plugin \"\(driver.pluginName)\", preset \(driver.presetName.map { "\"\($0)\"" } ?? "not known")\(options.wait ? ", waiting for CONTROL MAPPED" : "")")
        for (number, page) in ArturiaRotoDriver.pages.enumerated() {
            for (knob, control) in page.enumerated() {
                guard let control else { continue }
                let value = driver.value(forItem: control.item).map { "\($0) (\(ArturiaRotoDriver.valueText($0)))" } ?? "not known"
                print("             page \(number + 1), knob \(knob + 1): \(control.name), item \(control.item): \(value)")
            }
        }
    }

    /// Runs one command typed at the keyboard. Returns false for `quit`.
    func run(_ line: String) -> Bool {
        let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let command = words.first?.lowercased() else { return true }
        lock.lock()
        defer { lock.unlock() }
        switch command {
        case "quit", "exit", "q": return false
        case "help", "?": print(arturiaCommandHelp)
        case "status": printStatus()
        case "mark": log("mark  " + words.dropFirst().joined(separator: " "))
        default: log("Unknown command \"\(command)\". Type `help`.")
        }
        flushOutput()
        return true
    }

    func close() {
        device?.close()
        port?.close()
    }
}

func arturia(_ arguments: ArraySlice<String>) -> Never {
    let session = ArturiaSession(options: parseArturiaOptions(arguments))
    session.connect()
    session.startClock()
    var quit = false
    while let line = readLine() {
        if !session.run(line) { quit = true; break }
    }
    if !quit, !standardInputIsTerminal() {
        // Standard input is not a terminal and has ended: keep listening until Ctrl-C.
        while true { Thread.sleep(forTimeInterval: 60) }
    }
    session.close()
    exit(0)
}
