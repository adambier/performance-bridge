// sbdev arturia: a prototype that shows a standalone Arturia instrument on the Roto-Control's
// PLUGIN mode (docs/PLUGIN-MODE-PLAN.md, section 6). sbdev opens the device and runs the
// handshake as type 02, publishes a virtual port under a KeyLab keyboard's name for the
// instrument (a KeyLab mkII's by default), and runs the ArturiaRotoDriver library between the
// two. Run once, under the first KeyLab's name, with Pigments (docs/ARTURIA.md, test 2).

import Foundation
import RotoControl
import ArturiaControl
import ArturiaRotoDriver
import MIDITransport

let arturiaUsage = """
    Usage: sbdev arturia [--port NAME] [--keyboard NAME] [--wait] [--device NAME | --in NAME --out NAME]
                         [--gap MS] [--no-files] [--trust-files] [--library PATH] [--no-ask]
        Connects to the Roto-Control, runs the handshake as type 02, and publishes a virtual
        MIDI source and destination named NAME (--port; default "KeyLab mkII 61"), the name
        of a controller an Arturia instrument reports its values to. NAME must be one the
        KeyLab mkII's or the first KeyLab's profile lists (e.g., "KeyLab 61"); the tool talks
        to the instrument by that profile. In PLUGIN mode the Roto-Control is then offered
        one macro plugin with two pages:
          page 1   knobs 1–4: Macro 1–4;  knobs 5–8: four parameters of the instrument's own,
                   shown as Param 1–4 until the instrument names them
          page 2   knob 1: Volume
        In MIX mode sbdev shows a page of stand-in tracks, as `sbdev relay` does.
        This is a prototype for a test (docs/ARTURIA.md, test 2, is its one run so far, under
        the first KeyLab's name).

        Under the KeyLab mkII's name, the instrument answers a knob turned on the Roto-Control
        with the control's name and its value in words. The knob then shows that name (Analog
        Lab V: the preset's own label) until the preset changes, and the instrument's value
        text in place of a percentage. No instrument has been seen to send the names
        otherwise.

        Names before a knob is turned are read (never written) from the instrument's own files
        under /Library/Arturia (--library PATH for another place; --no-files to read none):
        knobs 5–8 and the volume from its factory MIDI assignments and parameter names, and
        knobs 1–4 from the loaded preset's file, which holds the preset's labels for the four
        macros. The preset is found by its name, its type, and its values as the instrument
        sends them; where presets of one name differ in their labels and those don't settle it,
        the knobs stay "Macro 1" to "Macro 4". Files are read only for Pigments, the one
        instrument they have been checked for (--trust-files reads them for any), and not for
        presets in Analog Lab V, which sends its own labels.

        With a real KeyLab mk3 (--keyboard NAME, its MIDI port, e.g., "KeyLab 61 mk3 MIDI"):
        an instrument talks to one controller at a time, so sbdev sits between the two. It
        opens the keyboard's port itself, publishes "KeyLab 88 mk3 MIDI" for the instrument
        (--port for another name), passes everything both ways, and reads the same stream for
        the Roto-Control, in the mk3's message format. In the instrument, check sbdev's port
        and uncheck the keyboard's own. A knob moved on either shows on the other. `status`
        prints how long the keyboard's messages spent in sbdev.

        Where sbdev has no names from files, it asks the instrument for them as a KeyLab mk3
        does when a knob is touched: it sends each knob's known value again, and the
        instrument answers with the name and the value in words. This moves a parameter by
        up to one 7-bit step and marks the preset as changed (seen); --no-ask turns it off.

        To try it:
          1. Quit Performance Bridge and every other sbdev tool, and every Arturia app.
          2. Start `sbdev arturia`, then the instrument.
          3. In the instrument's Audio MIDI Settings window, check the port under MIDI ports,
             and make sure Midi Controller (in its MIDI panel) reads "KeyLab mkII" (Pigments
             has needed it chosen by hand).
          4. Press MODE, then PLUGIN, on the Roto-Control.
        A control's name ends in "?" until the instrument reports its value. To make it
        report, move the control in the instrument's window, or load a preset.

        --wait sends LEARN PARAM only in answer to CONTROL MAPPED, which is the order of
        Melbourne Instruments' Bitwig integration; try it first. Without --wait, LEARN PARAM
        is sent unasked, which is this project's own variant. (--wait worked in test R1 and
        in test 2; without it is untested.)

        --device matches the Roto-Control's source and destination by name (default "Roto");
        --in and --out name them separately. --gap is the pause after each SysEx message sent
        to the Roto-Control (default 5 ms).

        Each line has the time since starting, the direction, the bytes, and what they mean:
          instrument → sbdev, sbdev → instrument   the virtual port
          device → sbdev, sbdev → device           the Roto-Control (PLUGIN mode's driver)
          local → device                           sbdev's handshake and MIX-mode page

    """ + arturiaCommandHelp

let arturiaCommandHelp = """
      status        prints the mode, the page, the plugin's name, and each control's name and value
      mark <text>   prints a line with the time and the text
      help          this list
      quit          removes the virtual ports and exits
    """

struct ArturiaOptions {
    var inName = "Roto"
    var outName = "Roto"
    var portName = "KeyLab mkII 61"
    var wait = false
    var readsFiles = true
    var trustsFiles = false
    var library = "/Library/Arturia"
    var keyboardName: String?
    var portWasGiven = false
    var asks = true
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
        case "--port": options.portName = value(argument); options.portWasGiven = true
        case "--keyboard": options.keyboardName = value(argument)
        case "--no-ask": options.asks = false
        case "--wait": options.wait = true
        case "--no-files": options.readsFiles = false
        case "--trust-files": options.trustsFiles = true
        case "--library": options.library = value(argument)
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
    if let keyboard = options.keyboardName, !options.portWasGiven {
        // A mk3 name the keyboard itself doesn't use.
        options.portName = keyboard.contains("88") ? "KeyLab 49 mk3 MIDI" : "KeyLab 88 mk3 MIDI"
    }
    guard let profile = ArturiaKeyLabProfile.forPortName(options.portName) else {
        fail("\"\(options.portName)\" is not a port name of the KeyLab mk3's, the KeyLab mkII's, or the first KeyLab's profile.")
    }
    if options.keyboardName != nil, profile.messageFormat != .version3 {
        fail("With --keyboard, the port needs a KeyLab mk3's name (e.g., \"KeyLab 88 mk3 MIDI\"), since the keyboard speaks that format.")
    }
    if options.keyboardName == options.portName {
        fail("The port needs a name the keyboard doesn't use.")
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
    private var keyboard: MIDIConnection?
    /// How long each of the keyboard's messages took to pass on, in seconds (the last 20,000).
    private var relayTimes: [Double] = []
    private let library: ArturiaLibrary?
    /// The instrument and the preset the files were last read for.
    private var namedInstrument: String?
    private var labeledPreset: [String?] = []
    private var port: VirtualMIDIPort?

    init(options: ArturiaOptions) {
        self.options = options
        library = options.readsFiles ? ArturiaLibrary(root: options.library, trustsUnchecked: options.trustsFiles) : nil
        driver = ArturiaRotoDriver(profile: ArturiaKeyLabProfile.forPortName(options.portName) ?? .keyLabMkII,
                                   waitsForControlMapped: options.wait)
        driver.asksForNames = options.asks
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
            if let name = options.keyboardName {
                keyboard = try MIDIConnection(clientName: "sbdev arturia", sourceName: name, destinationName: name) { [weak self] bytes in
                    self?.fromKeyboard(bytes)
                }
            }
        } catch {
            fail("\(error)")
        }
        log("Published a MIDI source and a MIDI destination named \"\(options.portName)\".")
        if let keyboard {
            log("Relaying between \"\(keyboard.source.name)\" and that port: check it in the instrument and uncheck the keyboard's own.")
        }
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

    /// The keyboard's bytes go on to the instrument before anything else is done with them.
    private func fromKeyboard(_ bytes: [UInt8]) {
        let arrived = Date()
        var failure: Error?
        do { try port?.send(bytes) } catch { failure = error }
        let passed = Date().timeIntervalSince(arrived)
        lock.lock()
        defer { lock.unlock() }
        relayTimes.append(passed)
        if relayTimes.count > 20_000 { relayTimes.removeFirst(10_000) }
        if let failure { log("   could not pass the keyboard's bytes on: \(failure)") }
        // Notes, pressure, and the wheels are passed on without a line each.
        if let status = bytes.first, status == 0xF0 || (0xB0...0xBF).contains(status) {
            log(arturiaLine("keyboard → instr.", bytes, "passed on"), at: arrived)
        }
        carryOut(driver.fromKeyboard(bytes, now: now(arrived)))
    }

    private func fromInstrument(_ bytes: [UInt8]) {
        let arrived = Date()
        var failure: Error?
        if let keyboard {
            do { try keyboard.send(bytes) } catch { failure = error }
        }
        lock.lock()
        defer { lock.unlock() }
        log(arturiaLine("instrument → sbdev", bytes, keyboard == nil ? "received" : "passed on to the keyboard"), at: arrived)
        if let failure { log("   could not pass the instrument's bytes on: \(failure)") }
        for message in assembler.feed(bytes) {
            if driver.profile.messageFormat == .version3 {
                if let parsed = ArturiaMk3Message.parse(message), let words = arturiaDescribe(parsed) { log("   " + words, at: arrived) }
            } else if let parsed = ArturiaInstrumentMessage.parse(message), let words = vportDescribe(parsed, profile: driver.profile) {
                log("   " + words, at: arrived)
            }
        }
        carryOut(driver.fromInstrument(bytes, now: now(arrived)))
        readFiles()
    }

    /// Reads the instrument's files when its text names a new instrument or a new preset, and
    /// gives the driver what they say. Called with the lock held.
    private func readFiles() {
        guard let library, let instrument = driver.instrumentName else { return }
        // Names are asked for only where no files are read for them.
        driver.asksForNames = options.asks && (driver.hostIsAnalogLab || !library.reads(instrument))
        if driver.hostIsAnalogLab {
            // Analog Lab V sends its own labels; what its presets' files say of them is unchecked.
            if namedInstrument != nil {
                namedInstrument = nil
                labeledPreset = []
                carryOut(driver.setParameterNames([:]))
                carryOut(driver.setPresetLabels(nil))
            }
            return
        }
        if instrument != namedInstrument {
            namedInstrument = instrument
            let names = library.parameterNames(instrument: instrument)
            log("   files: \(names.isEmpty ? "no parameter names read" : "parameter names for control changes \(names.keys.sorted().map(String.init).joined(separator: ", "))") (\(instrument))")
            carryOut(driver.setParameterNames(names))
        }
        guard let preset = driver.presetName else { return }
        let key = [instrument, preset, driver.presetKind]
        guard key != labeledPreset else { return }
        labeledPreset = key
        let values = driver.presetValues
        let found = library.macroLabels(instrument: instrument, preset: preset, kind: driver.presetKind ?? "",
                                        macroValues: values.macros, volume: values.volume,
                                        nameIsWhole: driver.profile.messageFormat == .version3)
        let words = found.labels.map { "macro labels " + $0.map { $0 ?? "-" }.joined(separator: ", ") } ?? "no macro labels"
        log("   files: \(words), from \(found.read) preset file\(found.read == 1 ? "" : "s") named like \"\(preset)\"")
        carryOut(driver.setPresetLabels(found.labels))
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
        for message in output.toKeyboard {
            guard let keyboard else { continue }
            log(arturiaLine("sbdev → keyboard", message, "a knob's value"))
            do { try keyboard.send(message) } catch { log("   could not send to the keyboard: \(error)") }
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
        log("profile \(driver.profile.name), \(driver.isInPluginMode ? "PLUGIN" : "MIX") mode, page \(driver.page + 1), plugin \"\(driver.pluginName)\", preset \(driver.presetName.map { "\"\($0)\"" } ?? "not known")\(options.wait ? ", waiting for CONTROL MAPPED" : "")")
        if keyboard != nil {
            let sorted = relayTimes.sorted()
            if sorted.isEmpty {
                print("             relay: nothing passed on from the keyboard yet")
            } else {
                func ms(_ seconds: Double) -> String { String(format: "%.3f ms", seconds * 1000) }
                print("             relay: \(sorted.count) messages from the keyboard passed on; time in sbdev: median \(ms(sorted[sorted.count / 2])), 99th percentile \(ms(sorted[min(sorted.count - 1, sorted.count * 99 / 100)])), longest \(ms(sorted[sorted.count - 1]))")
            }
        }
        for (number, page) in driver.pages.enumerated() {
            for (knob, control) in page.enumerated() {
                guard let control else { continue }
                let value = driver.value(forItem: control.item).map { "\($0) (\(ArturiaRotoDriver.valueText($0)))" } ?? "not known"
                let name = driver.name(forItem: control.item).map { "\"\($0)\" from the instrument" } ?? control.name
                print("             page \(number + 1), knob \(knob + 1): \(name), CC \(control.controller), item \(control.item): \(value)")
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
        lock.lock()
        printStatus()
        lock.unlock()
        keyboard?.close()
        device?.close()
        port?.close()
    }
}

/// What a message in the KeyLab mk3's format says, for the log.
func arturiaDescribe(_ message: ArturiaMk3Message) -> String? {
    switch message {
    case .connect(let on, let id): return "\(on ? "connect" : "disconnect")  (id \(id))"
    case .property(let item, 1, let value, _): return "value     item \(item) = \(value)"
    case .property(let item, let index, let value, _): return "property  \(index) of item \(item) = \(value)"
    case .preset(let name, let isChanged, let kind, let picture, _):
        return "preset    \"\(name)\"\(isChanged ? " (changed)" : ""), \"\(kind)\", picture \(picture.map(String.init) ?? "-")"
    case .controlScreen(let valueText, let name, let value, _):
        return "control   \"\(name)\", \"\(valueText)\", value \(value.map(String.init) ?? "-")"
    case .other: return nil
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
