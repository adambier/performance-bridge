// sbdev lcbridge: runs SurfaceCore and the Launch Control driver between TotalMix FX and a Launch
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
      sbdev lcbridge [--layout xl3 | lc3 | lc3-sim] [--host H] [--in-port P]
                     [--out-port P] [--port NAME] [--home N] [--meters]
                     [--numbers kind | all | none] [--verbose]
          Connects TotalMix FX and a Launch Control through SurfaceCore and the Launch Control
          driver, as the app will. Prints what is sent to TotalMix FX, with the time since starting;
          --verbose also prints every MIDI message to and from the device. Then reads commands
          from the keyboard (type `help`).
          --layout: xl3 (the default) for a Launch Control XL 3; lc3 for a Launch Control 3;
          lc3-sim for the Launch Control 3's layout on a Launch Control XL 3.
          --port names the device's DAW ports (default: found by name, "LCXL3 n DAW" or
          "LC3 n DAW" with the lowest device ID n).
          --host, --in-port, and --out-port are TotalMix FX's, as for monitor. --home is the home
          submix's output number, counting from 1 (default: TotalMix FX's Main Out).
          --numbers chooses how the meters' strips are numbered: kind (each kind counted on its
          own, the default), all (one count across inputs and playbacks), none (taller meters), or
          page (each strip's place on the page, 1–8).
          --meters draws the home screen as a picture with a meter for each strip (TotalMix FX's
          "Send Level Data" on).
          Stop sbdev monitor, sbdev bridge, and the app first: they need the same ports.

      On the device: Track < and > move by eight channels (with Shift, to the first or last
      page). XL 3: faders are level, the top two encoder rows sends (Page up and down choose
      the top row's output, Shift + Page the middle row's), the bottom row pan, the top
      buttons PFL, and the bottom buttons mute. Launch Control 3 (or lc3-sim): the bottom
      encoder row is level, the top row pan or a send (Page up and down), the buttons mute,
      and holding Function (Mute/Select on an XL 3) makes them PFL. Holding Shift for 0.3 s
      and turning an encoder resets it: pan to center, a level above 0 dB down to 0 dB, a
      send to -oo and back again.
    """

let lcBridgeCommandHelp = """
    Commands:
      home N | home main   the home submix: output N (from 1), or TotalMix FX's Main Out
      pbpage on | pbpage off   start the first playback on a new page, or not
      meters on | meters off   the home screen as meters, or as text
      numbers kind | all | none | page   how the meters' strips are numbered (see --numbers)
      peaks bar | floor    a held peak only over a bar (the default), or also alone above −40 dBFS
      fall off | N         let a bar fall with the average (the default), or at N dB a second at most
      order                the sources in the channel order, numbered from 1, with their names
      move A B             move the source at place A in that order to place B
      sendall              ask TotalMix FX for its state again
      status               the layout, the home submix, the send targets, and each layer's strips
      quit                 leave DAW mode and stop
    """

struct LaunchBridgeOptions {
    var endpoint = TotalMixEndpoint.standard
    var layout = LaunchControlModel.xl3
    var device = LaunchControlModel.xl3
    var portName: String?
    var home: Int?
    var verbose = false
    var meters = false
    var numbering = LaunchControlDriver.MeterNumbering.byKind
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
        case "--host": options.endpoint.host = value(argument)
        case "--in-port": options.endpoint.incomingPort = port(argument)
        case "--out-port": options.endpoint.outgoingPort = port(argument)
        case "--port": options.portName = value(argument)
        case "--home":
            guard let number = Int(value(argument)), number >= 1 else { fail("--home needs an output number from 1.") }
            options.home = number - 1
        case "--verbose": options.verbose = true
        case "--meters": options.meters = true
        case "--numbers":
            guard let numbering = LaunchControlDriver.MeterNumbering(rawValue: value(argument)) else {
                fail("--numbers is kind, all, none, or page.")
            }
            options.numbering = numbering
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
        driver = LaunchControlDriver(name: "lc", layout: options.layout, device: options.device, showsMeters: options.meters)
        driver.meterNumbering = options.numbering
    }

    private var now: Double { Date().timeIntervalSince(start) }

    func connect() {
        lock.lock()
        defer { lock.unlock() }
        let portName = options.portName
            ?? options.device.dawPort(among: MIDIConnection.sources().map(\.name)) ?? options.device.defaultPortName
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
        log("TotalMix FX at \(options.endpoint.host), sending to port \(options.endpoint.incomingPort), listening on \(options.endpoint.outgoingPort). \(layoutName): \"\(midi!.source.name)\". Type `help` for commands.")
        socket?.startReceiving { [weak self] bytes, _ in self?.fromTotalMix(bytes) }
        if let home = options.home { dispatch(hub.setHomeSubmix(home, now: now)) }
        dispatch(hub.connect(now: now))
        let started = driver.start(hub: &hub, now: now)
        send(started)

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
        if !driver.isConnected, !step.midi.isEmpty { log("No answer from the device yet; asking for DAW mode again") }
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
            log("→ TotalMix FX \(message.address) \(message.arguments.map(describe).joined(separator: " "))")
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
        case "meters":
            guard words.count == 2, words[1] == "on" || words[1] == "off" else {
                print("meters on or meters off")
                return true
            }
            var step = LaunchControlStep()
            step.midi = driver.setShowsMeters(words[1] == "on", hub: hub)
            send(step)
            log("Meters: \(driver.showsMeters ? "on" : "off")")
        case "numbers":
            guard words.count == 2, let numbering = LaunchControlDriver.MeterNumbering(rawValue: words[1]) else {
                print("numbers kind, all, none, or page")
                return true
            }
            driver.meterNumbering = numbering
            log("Numbering: \(numbering.rawValue)")
        case "peaks":
            guard words.count == 2, words[1] == "bar" || words[1] == "floor" else {
                print("peaks bar or peaks floor")
                return true
            }
            driver.meterPeakFloor = words[1] == "floor" ? -40 : nil
            log("Peaks: \(words[1] == "floor" ? "also alone above −40 dBFS" : "only over a bar")")
        case "fall":
            if words.count == 2, words[1] == "off" {
                driver.meterFall = nil
                log("Fall: with the average")
            } else if words.count == 2, let rate = Double(words[1]), rate > 0 {
                driver.meterFall = rate
                log("Fall: at most \(words[1]) dB a second")
            } else {
                print("fall off, or fall N (dB a second, e.g., fall 12)")
            }
        case "order":
            for (index, ref) in hub.layout.channels(.sources, in: hub.mirror).enumerated() {
                let name = hub.layout.label(for: ref) ?? hub.mirror.channels[ref]?.name ?? ""
                print("  \(index + 1). \(ref.bus == .playback ? "playback" : "input") \(ref.channel + 1): \(name)")
            }
        case "move":
            let order = hub.layout.channels(.sources, in: hub.mirror)
            guard words.count == 3, let from = Int(words[1]), let to = Int(words[2]),
                  order.indices.contains(from - 1), order.indices.contains(to - 1) else {
                print("move A B, with A and B places from `order` (1–\(order.count))")
                return true
            }
            var moved = order
            moved.insert(moved.remove(at: from - 1), at: to - 1)
            dispatch(hub.setLayout(hub.layout.withOrder(.sources, moved), now: now))
            log("Moved place \(from) to \(to)")
        case "sendall":
            dispatch(hub.connect(now: now))
        case "status":
            log("Connected: \(driver.isConnected); send rows: \(driver.sendOutputs.map { $0.map { "output \($0 + 1)" } ?? "auto/pan" }); buttons: \(driver.buttonsArePFL ? "PFL" : "mute")")
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
        // The socket waits for its receive thread, which may be waiting for the lock.
        socket?.stop()
        lock.lock()
        defer { lock.unlock() }
        let bytes = driver.stop(hub: &hub)
        try? midi?.send(bytes)
        Thread.sleep(forTimeInterval: 0.1)
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
    if !quit, !standardInputIsTerminal() {
        while true { Thread.sleep(forTimeInterval: 60) }
    }
    session.close()
    exit(0)
}
