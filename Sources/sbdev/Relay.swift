// sbdev relay: a prototype relay between a Roto-Control and Bitwig Studio's Roto-Control
// integration, for tests R2 and R4 of docs/PLUGIN-MODE-PLAN.md. sbdev opens the device and runs
// the handshake as type 02, publishes a virtual port pair for Bitwig Studio, and passes messages
// between the two by the rules in the RotoRelay library. Run once with a Roto-Control and Bitwig
// Studio (docs/ROTO-CONTROL.md, test 15).

import Foundation
import RotoControl
import RotoRelay
import ArturiaControl
import ArturiaNameRelay
import MIDITransport

let relayUsage = """
    Usage: sbdev relay [--port NAME] [--device NAME | --in NAME --out NAME] [--gap MS]
                       [--keyboard NAME [--keylab-port NAME] [--no-ask] [--no-preset]]
        Connects to the Roto-Control, runs the handshake as Bitwig Studio's type (02), and
        publishes a virtual MIDI source and destination named NAME (--port; default
        "PB Roto Relay"). Messages then pass between the Roto-Control and whatever program
        uses the virtual ports, by the mode the Roto-Control reports:
          PLUGIN mode   the program on the virtual ports has the Roto-Control
          MIX mode      sbdev has it (a page of stand-in tracks, as `sbdev roto` shows), and
                        the program's messages are dropped, except transport while the
                        transport switches are active
        This is a prototype for a test (docs/ROTO-CONTROL.md, test 15, is its one run so far).

        Before the test, in Bitwig Studio (Settings, Controllers; as seen in test 15):
          1. Find the "Melbourne Instruments Roto-Control" controller. Bitwig Studio has been
             observed to have it already, on the Roto-Control's own ports.
          2. Set both of its port menus (input and output) to the relay's port
             ("PB Roto Relay", or the name given with --port). Don't add the controller a
             second time from the list below it.
          3. After the test, set both menus back to "Roto-Control".
        Start `sbdev relay` first, so that the port exists. Quit every other program that
        opens the Roto-Control's ports (Performance Bridge, `sbdev roto`, `sbdev bridge`).
        The relay learns the mode from what the Roto-Control sends. If it has sent none yet,
        press MODE, then MIX, on the Roto-Control, then MODE, then PLUGIN. In Bitwig Studio,
        knob names have been observed to show only once Show Remote Controls is on.

        --device matches the Roto-Control's source and destination by name (default "Roto");
        --in and --out name them separately. --gap is the pause after each SysEx message sbdev
        itself sends to the Roto-Control (default 5 ms); passed messages are not paused.

        With a KeyLab mk3 (--keyboard NAME, its MIDI port, e.g., "KeyLab 61 mk3 MIDI"), the
        relay also sits between the keyboard and an Arturia plugin in the host, and puts the
        plugin's own names on the Roto-Control (docs/PLUGIN-MODE-PLAN.md, section 10, item 10;
        untested as a whole). It publishes a second port under another KeyLab mk3's name
        ("KeyLab 49 mk3 MIDI"; --keylab-port for another), which a plugin loaded afterward has
        been seen to take for its keyboard, and passes everything both ways. For Analog Lab V
        on the host's first page of controls it then:
          - replaces a knob's name with the plugin's ("FXA Dry/Wet" becomes "Chorus Mix")
          - sends the preset's name as the track's name (--no-preset turns this off)
          - asks the plugin for names it has not sent, by sending a knob's value again; this
            moves the parameter to the nearest of 128 steps and marks the preset as changed
            (--no-ask turns it off; names then come only as the keyboard's knobs are turned)
        Before the test, also in Bitwig Studio (Settings, Controllers): add the KeyLab port
        as a controller ("Generic", with the port as its input), so that control changes sent
        on it reach the plugin. Then add the plugin to a track (one loaded earlier stays on
        the keyboard itself: delete it and add it again).

        Each line has the time since starting, the direction, the bytes, and the rule:
          device → host, host → device   passed on
          device → local                 left for sbdev's own MIX-mode page and handshake
          relay → device, relay → host   sent by the relay itself (a replay, an answer, or
                                         the mode for a host that has started again)
          local → device                 sent by sbdev's handshake or MIX-mode page
          dropped host, dropped device   sent nowhere
          plugin → keyboard, keyboard → plugin   passed on (with --keyboard)
          names → device, names → plugin         a name put in, or asked for (with --keyboard)
        The stand-in MIX page is minimal: track names and send names only, with no levels,
        lights, or meters, and nothing happens when a MIX-mode control is moved.

    """ + relayCommandHelp

let relayCommandHelp = """
      status        prints the mode the relay takes the Roto-Control to be in
      mark <text>   prints a line with the time and the text
      help          this list
      quit          removes the virtual ports and exits
    """

struct RelayOptions {
    var inName = "Roto"
    var outName = "Roto"
    var portName = "PB Roto Relay"
    var gapMilliseconds = 5
    var keyboardName: String?
    var keyLabPortName: String?
    var asks = true
    var showsPreset = true
}

func parseRelayOptions(_ arguments: ArraySlice<String>) -> RelayOptions {
    var options = RelayOptions()
    var rest = arguments
    func value(_ option: String) -> String {
        guard let text = rest.popFirst() else { fail("\(option) needs a value.\n\n\(relayUsage)") }
        return text
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "--port": options.portName = value(argument)
        case "--device": let name = value(argument); options.inName = name; options.outName = name
        case "--in": options.inName = value(argument)
        case "--out": options.outName = value(argument)
        case "--gap":
            guard let gap = Int(value(argument)), gap >= 0 else { fail("--gap needs a number of milliseconds.") }
            options.gapMilliseconds = gap
        case "--keyboard": options.keyboardName = value(argument)
        case "--keylab-port": options.keyLabPortName = value(argument)
        case "--no-ask": options.asks = false
        case "--no-preset": options.showsPreset = false
        case "-h", "--help": print(relayUsage); exit(0)
        default: fail("Unknown option \(argument).\n\n\(relayUsage)")
        }
    }
    if let keyboard = options.keyboardName {
        // A mk3 name the keyboard itself doesn't use, as `sbdev arturia` chooses it.
        let port = options.keyLabPortName ?? (keyboard.contains("49") ? "KeyLab 88 mk3 MIDI" : "KeyLab 49 mk3 MIDI")
        guard ArturiaKeyLabProfile.forPortName(port)?.messageFormat == .version3 else {
            fail("--keylab-port needs a KeyLab mk3's port name (e.g., \"KeyLab 88 mk3 MIDI\").")
        }
        guard port != keyboard else { fail("The KeyLab port needs a name the keyboard doesn't use.") }
        options.keyLabPortName = port
    } else if options.keyLabPortName != nil || !options.asks || !options.showsPreset {
        fail("--keylab-port, --no-ask, and --no-preset need --keyboard.")
    }
    return options
}

/// The stand-in owner of MIX mode: the handshake, and a page of track and send names so that the
/// Roto-Control's screens are not blank. The same messages as `sbdev roto`'s default setup sends,
/// without its commands.
struct RelayLocalOwner {
    static let trackCount = 16
    static let sendCount = 16

    var handshake = RotoHandshake(hostType: .bitwig)
    private var firstTrack = 0
    private var selectedTrack = 0

    /// The messages to send to the device for one message left for the local owner.
    mutating func react(to message: RotoIncoming) -> [RotoOutgoing] {
        let (reply, justConnected) = handshake.handle(message)
        if justConnected {
            return reply + [.requestFirmwareVersion, .requestSysExAPIVersion, .meterThresholds(yellow: 87, red: 113)] + page(countFirst: true)
        }
        guard handshake.isConnected else { return reply }
        switch message {
        case .setFirstTrack(let first):
            firstTrack = first
            return page(countFirst: false)
        case .allTracksMode(let mode):
            return [.sendCount(Self.sendCount), sendNames(from: RotoOutgoing.sendNamesStart(forSendIndex: mode.sendIndex))]
                + page(countFirst: true)
        case .selectTrack(let index):
            selectedTrack = index
            return []
        case .requestSendNames(let index):
            return [sendNames(from: RotoOutgoing.sendNamesStart(forSendIndex: index))]
        case .singleTrackMode(let page):
            return [.sendCount(Self.sendCount),
                    sendNames(from: RotoOutgoing.sendNamesStart(forControlPage: page, numbering: .pageNumbers)),
                    .selectTrack(track(selectedTrack))]
        default:
            return reply
        }
    }

    private func track(_ index: Int) -> RotoTrackDetails {
        RotoTrackDetails(index: index, name: "Track \(index + 1)", colorScheme: UInt8((index * 11) % 83))
    }

    private func sendNames(from start: Int) -> RotoOutgoing {
        .sendNames(start: start, names: (start..<max(start, min(start + 8, Self.sendCount))).map { "Send \($0 + 1)" })
    }

    private func page(countFirst: Bool) -> [RotoOutgoing] {
        var messages: [RotoOutgoing] = countFirst ? [.trackCount(Self.trackCount)] : []
        messages.append(.firstTrack(firstTrack))
        for index in firstTrack..<max(firstTrack, min(firstTrack + 8, Self.trackCount)) {
            messages.append(.trackDetails(track(index), immediate: false))
        }
        messages.append(.trackDetailsEnd)
        return messages
    }
}

/// The relay with its two connections. One lock guards everything, since the device's bytes, the
/// host's bytes, and the keyboard's commands arrive on three threads.
final class RelaySession: @unchecked Sendable {
    private let options: RelayOptions
    private let lock = NSLock()
    private let start = Date()
    private var relay = RotoRelay()
    private var local = RelayLocalOwner()
    private var device: MIDIConnection?
    private var port: VirtualMIDIPort?
    /// With --keyboard: the names, the keyboard, and the port the plugin takes for a KeyLab.
    private var names: ArturiaNameRelay?
    private var keyboard: MIDIConnection?
    private var keyLabPort: VirtualMIDIPort?
    private var pluginMessages = ArturiaSysExAssembler()

    init(options: RelayOptions) {
        self.options = options
        if options.keyboardName != nil {
            var names = ArturiaNameRelay()
            names.asksForNames = options.asks
            names.showsPreset = options.showsPreset
            self.names = names
        }
    }

    func connect() {
        // Held until the handshake has started, so that input arriving meanwhile waits.
        lock.lock()
        defer { lock.unlock() }
        do {
            // The device first: the relay's own port ("PB Roto Relay") also matches the default
            // device name, "Roto", and once it exists the match is no longer a single port
            // (seen 2026-11-14: "No single MIDI port matches"). Input waits for the lock.
            device = try MIDIConnection(clientName: "sbdev relay", sourceName: options.inName, destinationName: options.outName) { [weak self] bytes in
                self?.fromDevice(bytes)
            }
            // The keyboard before the KeyLab port, for the same reason.
            if let name = options.keyboardName {
                keyboard = try MIDIConnection(clientName: "sbdev relay", sourceName: name, destinationName: name) { [weak self] bytes in
                    self?.fromKeyboard(bytes)
                }
            }
            port = try VirtualMIDIPort(clientName: "sbdev relay", name: options.portName) { [weak self] bytes in
                self?.fromHost(bytes)
            }
            if let name = options.keyLabPortName {
                keyLabPort = try VirtualMIDIPort(clientName: "sbdev relay", name: name) { [weak self] bytes in
                    self?.fromPlugin(bytes)
                }
            }
        } catch {
            fail("\(error)")
        }
        log("Published a MIDI source and a MIDI destination named \"\(options.portName)\".")
        if let keyboard, let name = options.keyLabPortName {
            log("Published another pair named \"\(name)\", relayed to and from \"\(keyboard.source.name)\".")
        }
        log("Listening to \"\(device!.source.name)\", sending to \"\(device!.destination.name)\". Type `help` for commands.")
        sendLocal(local.handshake.start())
    }

    /// Prints a line with the time since starting (or since `at`). Called with the lock held.
    private func log(_ text: String, at time: Date = Date()) {
        print(String(format: "%9.3f  ", time.timeIntervalSince(start)) + text)
        flushOutput()
    }

    private func fromDevice(_ bytes: [UInt8]) {
        let arrived = Date()
        lock.lock()
        defer { lock.unlock() }
        let before = (relay.knobMode, relay.transportSwitchesActive)
        let output = relay.fromDevice(bytes)
        carryOut(output, at: arrived)
        if before != (relay.knobMode, relay.transportSwitchesActive) { log("   " + status()) }
        for message in output.forLocal {
            guard let incoming = RotoIncoming(sysEx: message) else { continue }
            sendLocal(local.react(to: incoming), note: describe(incoming))
        }
    }

    private func fromHost(_ bytes: [UInt8]) {
        let arrived = Date()
        lock.lock()
        defer { lock.unlock() }
        carryOut(relay.fromHost(bytes), at: arrived)
    }

    /// Prints each decision and sends what it says to send. Called with the lock held.
    private func carryOut(_ output: RotoRelayOutput, at time: Date) {
        names?.isInPluginMode = relay.knobMode == .plugin
        let now = time.timeIntervalSince(start)
        for decision in output.decisions {
            switch decision.route {
            case .toHost:
                log(relayLine(decision.direction, decision.bytes, decision.rule), at: time)
                sendToHost(decision.bytes)
                if decision.source == .device, let extra = names?.fromDevice(decision.bytes, now: now) { carryOut(extra) }
            case .toDevice:
                // The host's names for an Arturia plugin's knobs are replaced on the way.
                let changed = names?.fromHost(decision.bytes, now: now)
                let bytes = changed?.message ?? decision.bytes
                log(relayLine(decision.direction, bytes, decision.rule + (bytes == decision.bytes ? "" : "; name replaced")), at: time)
                sendToDevice(bytes, gap: decision.source == .relay)
                if let extra = changed?.output { carryOut(extra) }
            case .forLocal, .dropped:
                log(relayLine(decision.direction, decision.bytes, decision.rule), at: time)
            }
        }
    }

    /// Prints and sends what the name relay returned. Called with the lock held.
    private func carryOut(_ output: ArturiaNameRelayOutput) {
        for note in output.notes { log("   names: " + note) }
        for message in output.toDevice {
            log(relayLine("names → device", message, RotoOutgoingDescription.words(message)))
            sendToDevice(message, gap: true)
        }
        for message in output.toInstrument {
            log(relayLine("names → plugin", message, "control change \(message.count > 2 ? "\(message[1]) = \(message[2])" : "")"))
            guard let keyLabPort else { continue }
            do { try keyLabPort.send(message) } catch { log("   could not send to the plugin's port: \(error)") }
        }
    }

    /// The keyboard's bytes go on to the plugin's port before anything else is done with them.
    private func fromKeyboard(_ bytes: [UInt8]) {
        let arrived = Date()
        var failure: Error?
        do { try keyLabPort?.send(bytes) } catch { failure = error }
        lock.lock()
        defer { lock.unlock() }
        if let failure { log("   could not pass the keyboard's bytes on: \(failure)") }
        // Notes, pressure, and the wheels are passed on without a line each.
        if let status = bytes.first, status == 0xF0 || (0xB0...0xBF).contains(status) {
            log(relayLine("keyboard → plugin", bytes, "passed on"), at: arrived)
        }
        names?.fromKeyboard(bytes, now: arrived.timeIntervalSince(start))
    }

    private func fromPlugin(_ bytes: [UInt8]) {
        let arrived = Date()
        var failure: Error?
        do { try keyboard?.send(bytes) } catch { failure = error }
        lock.lock()
        defer { lock.unlock() }
        log(relayLine("plugin → keyboard", bytes, "passed on"), at: arrived)
        if let failure { log("   could not pass the plugin's bytes on: \(failure)") }
        for message in pluginMessages.feed(bytes) {
            if let parsed = ArturiaMk3Message.parse(message), let words = arturiaDescribe(parsed) { log("   " + words, at: arrived) }
        }
        names?.isInPluginMode = relay.knobMode == .plugin
        if let output = names?.fromInstrument(bytes, now: arrived.timeIntervalSince(start)) { carryOut(output) }
    }

    /// Calls the name relay's `tick` every 50 ms, on a thread of its own, until the program exits.
    func startClock() {
        guard names != nil else { return }
        let thread = Thread { [weak self] in
            while let session = self {
                session.tick()
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.start()
    }

    private func tick() {
        lock.lock()
        defer { lock.unlock() }
        names?.isInPluginMode = relay.knobMode == .plugin
        if let output = names?.tick(now: Date().timeIntervalSince(start)) { carryOut(output) }
    }

    /// Sends the local owner's messages to the device, printing each. Called with the lock held.
    private func sendLocal(_ messages: [RotoOutgoing], note: String? = nil) {
        for message in messages {
            log(relayLine("local → device", message.bytes, describe(message) + (note.map { ", answering " + $0 } ?? "")))
            sendToDevice(message.bytes, gap: true)
        }
    }

    private func sendToDevice(_ bytes: [UInt8], gap: Bool) {
        guard let device else { log("   not sent: no connection"); return }
        do {
            try device.send(bytes)
        } catch {
            log("   could not send to the device: \(error)")
        }
        if gap, bytes.first == 0xF0, options.gapMilliseconds > 0 {
            Thread.sleep(forTimeInterval: Double(options.gapMilliseconds) / 1000)
        }
    }

    private func sendToHost(_ bytes: [UInt8]) {
        guard let port else { log("   not sent: no virtual port"); return }
        do {
            try port.send(bytes)
        } catch {
            log("   could not send to the host: \(error)")
        }
    }

    private func status() -> String {
        "mode: knobs in \(relay.knobMode == .plugin ? "PLUGIN" : "MIX") mode, transport switches \(relay.transportSwitchesActive ? "active" : "not active")"
            + (relay.firmwareVersionReply == nil ? ", firmware version not known" : "")
            + (names.map { names in
                let plugin = !names.isConnected ? "no plugin has connected to the KeyLab port"
                    : (names.isAnalogLab ? "Analog Lab V" : "a plugin that is not Analog Lab V") + " is on the KeyLab port"
                    + (names.presetName.map { ", preset \"\($0)\"" } ?? "")
                return "; \(plugin); host's plugin \(names.selectedPluginName.map { "\"\($0)\"" } ?? "none"); names \(names.isActive ? "on" : "off")"
            } ?? "")
    }

    /// Runs one command typed at the keyboard. Returns false for `quit`.
    func run(_ line: String) -> Bool {
        let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let command = words.first?.lowercased() else { return true }
        lock.lock()
        defer { lock.unlock() }
        switch command {
        case "quit", "exit", "q": return false
        case "help", "?": print(relayCommandHelp)
        case "status": log(status())
        case "mark": log("mark  " + words.dropFirst().joined(separator: " "))
        default: log("Unknown command \"\(command)\". Type `help`.")
        }
        flushOutput()
        return true
    }

    func close() {
        keyboard?.close()
        keyLabPort?.close()
        device?.close()
        port?.close()
    }
}

/// One line of the relay's log: the direction in a fixed column, the bytes, and the rule.
func relayLine(_ direction: String, _ bytes: [UInt8], _ rule: String) -> String {
    direction.padding(toLength: 15, withPad: " ", startingAt: 0) + " " + hex(bytes) + "   [\(rule)]"
}

func relay(_ arguments: ArraySlice<String>) -> Never {
    let session = RelaySession(options: parseRelayOptions(arguments))
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

/// What a Roto-Control message the name relay sends says, for the log.
enum RotoOutgoingDescription {
    static func words(_ message: [UInt8]) -> String {
        guard let (group, command, data) = RotoSysEx.unframe(message) else { return "" }
        switch (group, command) {
        case (0x0B, 0x0F) where data.count >= 8 + RotoSysEx.nameFieldLength:
            return "SET MAPPED CONTROL NAME \(RotoSysEx.decode14(data[0], data[1])) \"\(RotoSysEx.decodeName(data[8...]))\""
        case (0x0A, 0x16):
            return "SET CURRENT TRACK NAME \"\(RotoSysEx.decodeName(data))\""
        default:
            return ""
        }
    }
}
