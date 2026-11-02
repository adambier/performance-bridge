// sbdev lcbridge: runs SurfaceCore and the Launch Control driver between TotalMix and a Launch
// Control XL 3 or Launch Control 3, as the app will, for trying them before the app has them.

import Foundation
import OSCCodec
import TotalMixOSC
import LaunchControl
import MIDITransport
import UDPTransport
import SurfaceCore
import LaunchControlDriver

let lcBridgeUsage = """
    Usage:
      sbdev lcbridge [--layout xl3 | lc3 | lc3-sim] [--rows R,R,R] [--host H] [--in-port P]
                     [--out-port P] [--port NAME] [--home N] [--verbose]
          Connects TotalMix and a Launch Control through SurfaceCore and the Launch Control
          driver, as the app will. Prints what is sent to TotalMix, with the time since starting;
          --verbose also prints every MIDI message to and from the device. Then reads commands
          from the keyboard (type `help`).
          --layout: xl3 (the default) for a Launch Control XL 3; lc3 for a Launch Control 3;
          lc3-sim for the Launch Control 3's layout on a Launch Control XL 3.
          --rows: what the XL 3's encoder rows control, top to bottom, each pan or send
          (default send,send,pan, as in Novation's own DAW integrations).
          --port names the device's DAW ports (default "LCXL3 1 DAW", or "LC3 1 DAW" for lc3).
          --host, --in-port, and --out-port are TotalMix's, as for monitor. --home is the home
          submix's output number, counting from 1 (default: TotalMix's Main Out).
          Stop sbdev monitor, sbdev bridge, and the app first: they need the same ports.

      On the device: Track < and > move by eight strips (with Shift, to the first or last
      page); Page up and down
      step the sends; Shift with Page up shows the sources, with Page down the outputs. XL 3: faders are
      level, top buttons PFL, bottom buttons mute. Launch Control 3 (or lc3-sim): the bottom
      encoder row is level, the top row pan or a send (Page up and down), the buttons mute, and
      Function (Mute/Select on an XL 3) switches them to PFL.
    """

let lcBridgeCommandHelp = """
    Commands:
      rows R R R           XL 3: what the encoder rows control, top to bottom (pan or send)
      home N | home main   the home submix: output N (from 1), or TotalMix's Main Out
      pbpage on | pbpage off   start the first playback on a new page, or not
      sendall              ask TotalMix for its state again
      status               the layout, the home submix, the send targets, and each layer's strips
      quit                 leave DAW mode and stop
    """

struct LaunchBridgeOptions {
    var endpoint = TotalMixEndpoint.standard
    var layout = LaunchControlModel.xl3
    var device = LaunchControlModel.xl3
    var rows = LaunchControlDriver.defaultRows
    var rowsGiven = false
    var portName: String?
    var home: Int?
    var verbose = false
}

func parseRowFunctions(_ words: [String]) -> [LaunchControlRowFunction]? {
    let functions = words.compactMap { LaunchControlRowFunction(rawValue: $0.lowercased()) }
    return functions.count == words.count && (1...3).contains(functions.count) ? functions : nil
}

func parseLaunchBridgeOptions(_ arguments: ArraySlice<String>) -> LaunchBridgeOptions {
    var options = LaunchBridgeOptions()
    var rest = arguments
    func value(_ option: String) -> String {
        guard let text = rest.popFirst() else { fail("\(option) needs a value.\n\n\(lcBridgeUsage)") }
        return text
    }
    func port(_ option: String) -> UInt16 {
        guard let number = UInt16(value(option)), number > 0 else { fail("\(option) needs a port number.") }
        return number
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "--layout":
            switch value(argument).lowercased() {
            case "xl3": (options.layout, options.device) = (.xl3, .xl3)
            case "lc3": (options.layout, options.device) = (.lc3, .lc3)
            case "lc3-sim": (options.layout, options.device) = (.lc3, .xl3)
            default: fail("--layout is xl3, lc3, or lc3-sim.")
            }
        case "--rows":
            guard let rows = parseRowFunctions(value(argument).split(separator: ",").map(String.init)) else {
                fail("--rows takes up to three of pan and send, separated by commas (e.g., send,send,pan).")
            }
            options.rows = rows
            options.rowsGiven = true
        case "--host": options.endpoint.host = value(argument)
        case "--in-port": options.endpoint.incomingPort = port(argument)
        case "--out-port": options.endpoint.outgoingPort = port(argument)
        case "--port": options.portName = value(argument)
        case "--home":
            guard let number = Int(value(argument)), number >= 1 else { fail("--home needs an output number from 1.") }
            options.home = number - 1
        case "--verbose": options.verbose = true
        case "-h", "--help": print(lcBridgeUsage); exit(0)
        default: fail("Unknown option \(argument).\n\n\(lcBridgeUsage)")
        }
    }
    return options
}

/// The hub, the driver, and their connections. Every change happens with the lock held.
final class LaunchBridgeSession: @unchecked Sendable {
    private let options: LaunchBridgeOptions
    private let lock = NSLock()
    private let start = Date()
    private var hub = SurfaceHub()
    private var driver: LaunchControlDriver
    private var socket: UDPSocket?
    private var midi: MIDIConnection?
    private var wasConnected = false

    init(options: LaunchBridgeOptions) {
        self.options = options
        driver = LaunchControlDriver(name: "lc", layout: options.layout, device: options.device)
    }

    private var now: Double { Date().timeIntervalSince(start) }

    func connect() {
        lock.lock()
        defer { lock.unlock() }
        let portName = options.portName ?? options.device.defaultPortName
        do {
            socket = try UDPSocket(listeningOn: options.endpoint.outgoingPort)
            midi = try MIDIConnection(clientName: "sbdev lcbridge", sourceName: portName,
                                      destinationName: portName) { [weak self] bytes in
                self?.fromDevice(bytes)
            }
        } catch {
            fail("\(error)")
        }
        let layoutName = options.layout == options.device ? options.layout.name
            : "\(options.layout.name)'s layout on a \(options.device.name)"
        log("TotalMix at \(options.endpoint.host), sending to port \(options.endpoint.incomingPort), listening on \(options.endpoint.outgoingPort). \(layoutName): \"\(midi!.source.name)\". Type `help` for commands.")
        socket?.startReceiving { [weak self] bytes, _ in self?.fromTotalMix(bytes) }
        if let home = options.home { dispatch(hub.setHomeSubmix(home, now: now)) }
        dispatch(hub.connect(now: now))
        let started = driver.start(hub: &hub, now: now)
        send(started)
        if options.layout == .xl3 {
            send(driver.setRowFunctions(options.rows, hub: &hub, now: now))
        } else if options.rowsGiven {
            log("--rows is for the XL 3's layout; the Launch Control 3's top row is stepped with Page up and down.")
        }

        let ticker = Thread { [weak self] in
            while let session = self {
                session.tick()
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        ticker.name = "lcbridge tick"
        ticker.start()
    }

    private func fromTotalMix(_ bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        guard let packet = try? OSCPacket(decoding: bytes) else { return }
        for message in packet.messages {
            guard let event = TotalMixEvent(message) else { continue }
            dispatch(hub.handle(event, now: now))
        }
    }

    private func fromDevice(_ bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        if options.verbose { log("← device \(hex(bytes))") }
        send(driver.receive(bytes, hub: &hub, now: now))
        if driver.isConnected && !wasConnected {
            wasConnected = true
            log("The device answered: DAW mode")
        }
    }

    private func tick() {
        lock.lock()
        defer { lock.unlock() }
        dispatch(hub.tick(now: now))
        let step = driver.tick(hub: &hub, now: now)
        if !step.midi.isEmpty { log("No answer from the device yet; asking for DAW mode again") }
        send(step)
    }

    private func dispatch(_ output: CoreOutput) {
        send(driver.take(output, hub: &hub, now: now))
    }

    private func send(_ step: LaunchControlStep) {
        for message in step.core.messages {
            do {
                try socket?.send(message.encoded(), to: options.endpoint.host, port: options.endpoint.incomingPort)
            } catch {
                log("Could not send \(message.address): \(error)")
            }
            log("→ TotalMix \(message.address) \(message.arguments.map(describe).joined(separator: " "))")
        }
        guard !step.midi.isEmpty else { return }
        do {
            try midi?.send(step.midi)
        } catch {
            log("Could not send to the device: \(error)")
        }
        if options.verbose { log("→ device \(hex(step.midi))") }
    }

    private func log(_ text: String) {
        print(String(format: "%9.3f  ", now) + text)
        flushOutput()
    }

    func run(_ line: String) -> Bool {
        let words = line.split(separator: " ").map(String.init)
        guard let command = words.first else { return true }
        lock.lock()
        defer { lock.unlock() }
        switch command {
        case "quit", "exit":
            return false
        case "help":
            print(lcBridgeCommandHelp)
        case "rows":
            guard options.layout == .xl3, let rows = parseRowFunctions(Array(words.dropFirst())) else {
                print(options.layout == .xl3 ? "rows R R R (each pan or send)" : "rows is for the XL 3's layout")
                return true
            }
            send(driver.setRowFunctions(rows, hub: &hub, now: now))
            log("Encoder rows: \(driver.rowFunctions.map(\.rawValue).joined(separator: ", "))")
        case "home":
            if words.count == 2, words[1] == "main" {
                dispatch(hub.setHomeSubmix(nil, now: now))
            } else if words.count == 2, let number = Int(words[1]), number >= 1 {
                dispatch(hub.setHomeSubmix(number - 1, now: now))
            } else {
                print("home N (an output, from 1) or home main")
            }
            log("Home submix: \(hub.homeSubmix.map { "output \($0 + 1)" } ?? "none yet")")
        case "pbpage":
            guard words.count == 2, words[1] == "on" || words[1] == "off" else {
                print("pbpage on or pbpage off")
                return true
            }
            var layout = hub.layout
            layout.playbacksOnNewPage = words[1] == "on"
            dispatch(hub.setLayout(layout, now: now))
        case "sendall":
            dispatch(hub.connect(now: now))
        case "status":
            log("Connected: \(driver.isConnected); view: \(driver.view == .sources ? "sources" : "outputs"); send step: \(driver.sendStep); buttons: \(driver.buttonsArePFL ? "PFL" : "mute" )")
            log("Home submix: \(hub.homeSubmix.map { "output \($0 + 1)" } ?? "none yet"); send targets: \(hub.sendTargets.map { "output \($0 + 1)" })")
            for layer in driver.layers {
                let id = driver.id(layer)
                log("\(layer.rawValue): \(hub.mode(of: id).map(describe) ?? "none")")
                for (index, strip) in (hub.strips(of: id) ?? []).enumerated() {
                    guard let info = strip.info else { continue }
                    log("  \(index + 1) \(info.name): knob \(info.knobLabel), switch \(info.switchLabel)")
                }
            }
        default:
            print("Unknown command. Type `help`.")
        }
        return true
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        let bytes = driver.stop(hub: &hub)
        try? midi?.send(bytes)
        Thread.sleep(forTimeInterval: 0.1)
        socket?.stop()
        midi?.close()
    }
}

func launchBridge(_ arguments: ArraySlice<String>) -> Never {
    let session = LaunchBridgeSession(options: parseLaunchBridgeOptions(arguments))
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
