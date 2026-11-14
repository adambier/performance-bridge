// sbdev relay: a prototype relay between a Roto-Control and Bitwig Studio's Roto-Control
// integration, for tests R2 and R4 of docs/PLUGIN-MODE-PLAN.md. sbdev opens the device and runs
// the handshake as type 02, publishes a virtual port pair for Bitwig Studio, and passes messages
// between the two by the rules in the RotoRelay library. Nothing here has been tested on the
// device or with Bitwig Studio.

import Foundation
import RotoControl
import RotoRelay
import MIDITransport

let relayUsage = """
    Usage: sbdev relay [--port NAME] [--device NAME | --in NAME --out NAME] [--gap MS]
        Connects to the Roto-Control, runs the handshake as Bitwig Studio's type (02), and
        publishes a virtual MIDI source and destination named NAME (--port; default
        "PB Roto Relay"). Messages then pass between the Roto-Control and whatever program
        uses the virtual ports, by the mode the Roto-Control reports:
          PLUGIN mode   the program on the virtual ports has the Roto-Control
          MIX mode      sbdev has it (a page of stand-in tracks, as `sbdev roto` shows), and
                        the program's messages are dropped, except transport while the
                        transport switches are active
        This is a prototype for a test. Whether it works is what the test is to find out.

        Before the test, in Bitwig Studio's controller settings:
          1. Remove any Roto-Control controller that Bitwig Studio added by itself on the
             Roto-Control's own ports.
          2. Add the Melbourne Instruments Roto-Control controller by hand.
          3. Set its MIDI input port and its MIDI output port to the relay's port
             ("PB Roto Relay", or the name given with --port).
        Start `sbdev relay` first, so that the port exists. Quit every other program that
        opens the Roto-Control's ports (Performance Bridge, `sbdev roto`, `sbdev bridge`).
        The relay learns the mode from what the Roto-Control sends. If it has sent none yet,
        press MIX on the Roto-Control, then PLUGIN.

        --device matches the Roto-Control's source and destination by name (default "Roto");
        --in and --out name them separately. --gap is the pause after each SysEx message sbdev
        itself sends to the Roto-Control (default 5 ms); passed messages are not paused.

        Each line has the time since starting, the direction, the bytes, and the rule:
          device → host, host → device   passed on
          device → local                 left for sbdev's own MIX-mode page and handshake
          relay → device, relay → host   sent by the relay itself (a replay, or an answer)
          local → device                 sent by sbdev's handshake or MIX-mode page
          dropped host, dropped device   sent nowhere
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
        case "-h", "--help": print(relayUsage); exit(0)
        default: fail("Unknown option \(argument).\n\n\(relayUsage)")
        }
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

    init(options: RelayOptions) {
        self.options = options
    }

    func connect() {
        // Held until the handshake has started, so that input arriving meanwhile waits.
        lock.lock()
        defer { lock.unlock() }
        do {
            port = try VirtualMIDIPort(clientName: "sbdev relay", name: options.portName) { [weak self] bytes in
                self?.fromHost(bytes)
            }
            device = try MIDIConnection(clientName: "sbdev relay", sourceName: options.inName, destinationName: options.outName) { [weak self] bytes in
                self?.fromDevice(bytes)
            }
        } catch {
            fail("\(error)")
        }
        log("Published a MIDI source and a MIDI destination named \"\(options.portName)\".")
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
        for decision in output.decisions {
            log(relayLine(decision.direction, decision.bytes, decision.rule), at: time)
            switch decision.route {
            case .toHost: sendToHost(decision.bytes)
            case .toDevice: sendToDevice(decision.bytes, gap: decision.source == .relay)
            case .forLocal, .dropped: break
            }
        }
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
