// sbdev bridge: runs SurfaceCore and the Roto-Control driver between TotalMix and a Roto-Control,
// as the app will, for trying them on the hardware before the app exists.

import Foundation
import OSCCodec
import TotalMixOSC
import RotoControl
import MIDITransport
import UDPTransport
import SurfaceCore
import RotoDriver

let bridgeUsage = """
    Usage:
      sbdev bridge [--host H] [--in-port P] [--out-port P] [--port NAME] [--home N] [--verbose]
          Connects TotalMix and a Roto-Control through SurfaceCore and the Roto-Control driver,
          as the app will. Prints what is sent to TotalMix and the Roto-Control's SysEx messages,
          with the time since starting; --verbose also prints what TotalMix sends (not /level
          or /status) and every MIDI message to the Roto-Control. Then reads commands from the
          keyboard (type `help`).
          --host, --in-port, and --out-port are TotalMix's, as for monitor. --port names the
          Roto-Control's MIDI ports (default "Roto"). --home is the home submix's output number,
          counting from 1 as TotalMix's window does (default: TotalMix's Main Out).
          Meters need "Send Level Data" on in TotalMix's OSC settings. Stop sbdev monitor
          first: both need the outgoing port.
    """

let bridgeCommandHelp = """
    Commands:
      home N | home main   the home submix: output N (from 1), or TotalMix's Main Out
      solo on | solo off   allow or forbid solo on the switches (off at the start)
      menu TEXT            test: send SET CURRENT TRACK NAME with TEXT, to see where it shows
      sendall              ask TotalMix for its state again
      status               the mode, the home submix, the send targets, and the strips
      quit
    """

struct BridgeOptions {
    var endpoint = TotalMixEndpoint.standard
    var portName = "Roto"
    var home: Int?
    var verbose = false
}

func parseBridgeOptions(_ arguments: ArraySlice<String>) -> BridgeOptions {
    var options = BridgeOptions()
    var rest = arguments
    func value(_ option: String) -> String {
        guard let text = rest.popFirst() else { fail("\(option) needs a value.\n\n\(bridgeUsage)") }
        return text
    }
    func port(_ option: String) -> UInt16 {
        guard let number = UInt16(value(option)), number > 0 else { fail("\(option) needs a port number.") }
        return number
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "--host": options.endpoint.host = value(argument)
        case "--in-port": options.endpoint.incomingPort = port(argument)
        case "--out-port": options.endpoint.outgoingPort = port(argument)
        case "--port": options.portName = value(argument)
        case "--home":
            guard let number = Int(value(argument)), number >= 1 else { fail("--home needs an output number from 1.") }
            options.home = number - 1
        case "--verbose": options.verbose = true
        case "-h", "--help": print(bridgeUsage); exit(0)
        default: fail("Unknown option \(argument).\n\n\(bridgeUsage)")
        }
    }
    return options
}

/// The hub, the driver, and their connections. Every change happens with the lock held.
final class BridgeSession: @unchecked Sendable {
    private let options: BridgeOptions
    private let lock = NSLock()
    private let start = Date()
    private var hub = SurfaceHub()
    private var driver = RotoDriver(id: SurfaceID("roto"))
    private var socket: UDPSocket?
    private var midi: MIDIConnection?
    private var oscDecodeErrors = 0

    init(options: BridgeOptions) {
        self.options = options
    }

    private var now: Double { Date().timeIntervalSince(start) }

    func connect() {
        lock.lock()
        defer { lock.unlock() }
        do {
            socket = try UDPSocket(listeningOn: options.endpoint.outgoingPort)
            midi = try MIDIConnection(clientName: "sbdev bridge", sourceName: options.portName,
                                      destinationName: options.portName) { [weak self] bytes in
                self?.fromRoto(bytes)
            }
        } catch {
            fail("\(error)")
        }
        log("TotalMix at \(options.endpoint.host), sending to port \(options.endpoint.incomingPort), listening on \(options.endpoint.outgoingPort). Roto-Control: \"\(midi!.source.name)\". Type `help` for commands.")
        socket?.startReceiving { [weak self] bytes, _ in self?.fromTotalMix(bytes) }
        dispatch(hub.addSurface(driver.id, capabilities: RotoDriver.capabilities, now: now))
        if let home = options.home { dispatch(hub.setHomeSubmix(home, now: now)) }
        dispatch(hub.connect(now: now))
        sendToRoto(driver.start())

        let ticker = Thread { [weak self] in
            while let session = self {
                session.tick()
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        ticker.name = "bridge tick"
        ticker.start()
    }

    // MARK: Input

    private func fromTotalMix(_ bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        guard let packet = try? OSCPacket(decoding: bytes) else {
            oscDecodeErrors += 1
            return
        }
        for message in packet.messages {
            guard let event = TotalMixEvent(message) else { continue }
            if options.verbose, !message.address.hasPrefix("/level"), !message.address.hasPrefix("/status") {
                log("← TotalMix \(message.address) \(message.arguments.map(describe).joined(separator: " "))")
            }
            dispatch(hub.handle(event, now: now))
        }
    }

    private func fromRoto(_ bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        if bytes.first == 0xF0, let message = RotoIncoming(sysEx: bytes) {
            log("← Roto \(describe(message))")
        }
        // Switches, transport switches, and anything else that is not a knob or a touch, for the
        // tests: a CC on channel 16 outside the knob (12–19, 44–51) and touch (52–59) blocks.
        var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == 0xBF {
                let controller = bytes[index + 1], value = bytes[index + 2]
                let knobOrTouch = (12...19).contains(controller) || (44...59).contains(controller)
                if !knobOrTouch { log("← Roto CC \(controller) = \(value)") }
                index += 3
            } else {
                index += 1
            }
        }
        let step = driver.receive(bytes, hub: &hub, now: now)
        sendToRoto(step.midi)
        dispatch(step.core)
    }

    private func tick() {
        lock.lock()
        defer { lock.unlock() }
        dispatch(hub.tick(now: now))
    }

    // MARK: Output

    private func dispatch(_ output: CoreOutput) {
        for message in output.messages {
            do {
                try socket?.send(message.encoded(), to: options.endpoint.host, port: options.endpoint.incomingPort)
            } catch {
                log("Could not send \(message.address): \(error)")
            }
            log("→ TotalMix \(message.address) \(message.arguments.map(describe).joined(separator: " "))")
        }
        for (id, updates) in output.updates where id == driver.id {
            sendToRoto(driver.render(updates, hub: hub))
        }
    }

    private func sendToRoto(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        do {
            try midi?.send(bytes)
        } catch {
            log("Could not send to the Roto-Control: \(error)")
        }
        if options.verbose { log("→ Roto \(hex(bytes))") }
    }

    private func log(_ text: String) {
        print(String(format: "%9.3f  ", now) + text)
        flushOutput()
    }

    // MARK: Commands

    /// Runs one command typed at the keyboard. Returns false for `quit`.
    func run(_ line: String) -> Bool {
        let words = line.split(separator: " ").map(String.init)
        guard let command = words.first else { return true }
        lock.lock()
        defer { lock.unlock() }
        switch command {
        case "quit", "exit":
            return false
        case "help":
            print(bridgeCommandHelp)
        case "home":
            if words.count == 2, words[1] == "main" {
                dispatch(hub.setHomeSubmix(nil, now: now))
            } else if words.count == 2, let number = Int(words[1]), number >= 1 {
                dispatch(hub.setHomeSubmix(number - 1, now: now))
            } else {
                print("home N (an output, from 1) or home main")
            }
            log("Home submix: \(hub.homeSubmix.map { "output \($0 + 1)" } ?? "none yet")")
        case "solo":
            guard words.count == 2, words[1] == "on" || words[1] == "off" else {
                print("solo on or solo off")
                return true
            }
            dispatch(hub.setSoloEnabled(words[1] == "on", now: now))
        case "menu":
            // A test: where does SET CURRENT TRACK NAME show? (docs/ROTO-CONTROL.md, section 8)
            let text = words.dropFirst().joined(separator: " ")
            sendToRoto(RotoOutgoing.currentTrackName(text).bytes)
            log("→ Roto SET CURRENT TRACK NAME \"\(text)\"")
        case "sendall":
            dispatch(hub.connect(now: now))
        case "status":
            log("Mode: \(hub.mode(of: driver.id).map { "\($0)" } ?? "none"); connected: \(driver.isConnected)")
            log("Home submix: \(hub.homeSubmix.map { "output \($0 + 1)" } ?? "none yet"); send targets: \(hub.sendTargets.map { "output \($0 + 1)" })")
            for (index, strip) in (hub.strips(of: driver.id) ?? []).enumerated() {
                let name = strip.info.map { "\($0.name) (\($0.channel))" } ?? "blank"
                log("  strip \(index + 1): \(name); knob \(strip.knobTarget.map { "\($0)" } ?? "none"); switch \(strip.switchTarget.map { "\($0)" } ?? "none")")
            }
            if oscDecodeErrors > 0 { log("Packets from TotalMix that were not OSC: \(oscDecodeErrors)") }
        default:
            print("Unknown command. Type `help`.")
        }
        return true
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        socket?.stop()
        midi?.close()
    }
}

func bridge(_ arguments: ArraySlice<String>) -> Never {
    let session = BridgeSession(options: parseBridgeOptions(arguments))
    session.connect()
    var quit = false
    while let line = readLine() {
        if !session.run(line) { quit = true; break }
    }
    if !quit, isatty(fileno(stdin)) == 0 {
        while true { Thread.sleep(forTimeInterval: 60) }
    }
    session.close()
    exit(0)
}
