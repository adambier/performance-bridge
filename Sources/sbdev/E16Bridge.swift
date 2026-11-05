// sbdev e16bridge: runs SurfaceCore and the E16 driver between TotalMix FX and an OXI E16, as the
// app does, for trying the layout on the device.

import Foundation
import OSCCodec
import TotalMixOSC
import MIDITransport
import UDPTransport
import SurfaceCore
import OXIE16
import E16Driver

let e16BridgeUsage = """
    Usage:
      sbdev e16bridge [--host H] [--in-port P] [--out-port P] [--port NAME] [--home N]
                      [--pan-center A,B,C…] [--pan-pause S] [--verbose]
          Connects TotalMix FX and an OXI E16 (in its Remote Mode) through SurfaceCore and the E16
          driver, as the app does. Prints what is sent to TotalMix FX, with the time since
          starting; --verbose also prints every MIDI message to and from the device. Then reads
          commands from the keyboard (type `help`).
          --port names the device's first USB port (default "OXI E16 Port 1").
          --host, --in-port, and --out-port are TotalMix FX's, as for monitor. --home is the home
          submix's output number, counting from 1 (default: TotalMix FX's Main Out).
          --pan-center gives the pans' sticky center a different number of units per encoder, to
          compare them side by side: with 2,5,10, encoders 1, 4, 7… take 2, encoders 2, 5, 8…
          take 5, and encoders 3, 6, 9… take 10 (default: the driver's 4 on every encoder).
          --pan-pause is how long, in seconds, a turn that stopped at center must pause before
          turning moves on (default 0.25).
          Stop sbdev monitor, the other bridges, and the app first: they need the same ports.

      On the device: turn is level, pan, or a send, by the mode; push and release is mute; a hold of
      one second is PFL; with Shift held the encoders are buttons: 1 LEVEL, 2 PAN, 3 SEND, 11 and 12
      the previous and next send output, 15 and 16 the previous and next page. Control-C or `quit`
      gives the device back.
    """

let e16BridgeCommandHelp = """
    Commands:
      home N | home main   the home submix: output N (from 1), or TotalMix FX's Main Out
      pbpage on | pbpage off   start the first playback on a new page, or not
      sendall              ask TotalMix FX for its state again
      status               the function, the home submix, the send targets, and the strips
      quit                 leave Remote Mode and stop
    """

struct E16BridgeOptions {
    var endpoint = TotalMixEndpoint.standard
    var portName = "OXI E16 Port 1"
    var home: Int?
    var panCenter: [Int] = []
    var panPause: Double?
    var verbose = false
}

func parseE16BridgeOptions(_ arguments: ArraySlice<String>) -> E16BridgeOptions {
    var options = E16BridgeOptions()
    var rest = arguments
    func value(_ option: String) -> String {
        guard let text = rest.popFirst() else { fail("\(option) needs a value.\n\n\(e16BridgeUsage)") }
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
        case "--pan-center":
            let units = value(argument).split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !units.isEmpty, units.allSatisfy({ ($0 ?? -1) >= 0 }) else { fail("--pan-center needs numbers from 0, separated by commas.") }
            options.panCenter = units.compactMap { $0 }
        case "--pan-pause":
            guard let seconds = Double(value(argument)), seconds >= 0, seconds.isFinite else { fail("--pan-pause needs seconds from 0.") }
            options.panPause = seconds
        case "--verbose": options.verbose = true
        case "-h", "--help": print(e16BridgeUsage); exit(0)
        default: fail("Unknown option \(argument).\n\n\(e16BridgeUsage)")
        }
    }
    return options
}

/// The hub, the driver, and their connections. Every change happens with the lock held.
final class E16BridgeSession: @unchecked Sendable {
    private let options: E16BridgeOptions
    private let lock = NSLock()
    private let start = Date()
    private var hub = SurfaceHub()
    private var driver = E16Driver(name: "e16")
    private var socket: UDPSocket?
    private var midi: MIDIConnection?
    private var wasConnected = false

    init(options: E16BridgeOptions) {
        self.options = options
        driver.panCenterTrial = options.panCenter
        if let pause = options.panPause { driver.panCenterPause = pause }
    }

    private var now: Double { Date().timeIntervalSince(start) }

    func connect() {
        lock.lock()
        defer { lock.unlock() }
        do {
            socket = try UDPSocket(listeningOn: options.endpoint.outgoingPort)
            midi = try MIDIConnection(clientName: "sbdev e16bridge", sourceName: options.portName,
                                      destinationName: options.portName) { [weak self] bytes in
                self?.fromDevice(bytes)
            }
        } catch {
            fail("\(error)")
        }
        log("TotalMix FX at \(options.endpoint.host), sending to port \(options.endpoint.incomingPort), listening on \(options.endpoint.outgoingPort). E16: \"\(midi!.source.name)\". Type `help` for commands.")
        socket?.startReceiving { [weak self] bytes, _ in self?.fromTotalMix(bytes) }
        if let home = options.home { dispatch(hub.setHomeSubmix(home, now: now)) }
        dispatch(hub.connect(now: now))
        send(driver.start(hub: &hub, now: now))

        let ticker = Thread { [weak self] in
            while let session = self {
                session.tick()
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        ticker.name = "e16bridge tick"
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
            log("The device answered: Remote Mode")
        }
    }

    private func tick() {
        lock.lock()
        defer { lock.unlock() }
        dispatch(hub.tick(now: now))
        let step = driver.tick(hub: &hub, now: now)
        if !driver.isConnected, !step.midi.isEmpty { log("No answer from the device yet; asking for Remote Mode again") }
        send(step)
    }

    private func dispatch(_ output: CoreOutput) {
        send(driver.take(output, hub: &hub, now: now))
    }

    private func send(_ step: E16Step) {
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
            print(e16BridgeCommandHelp)
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
            log("Connected: \(driver.isConnected); function: \(driver.function); title: \"\(driver.title(hub: hub))\"")
            log("Home submix: \(hub.homeSubmix.map { "output \($0 + 1)" } ?? "none yet"); send targets: \(hub.sendTargets.map { "output \($0 + 1)" })")
            let id = driver.id(.main)
            log("main: \(hub.mode(of: id).map(describe) ?? "none")")
            for (index, strip) in (hub.strips(of: id) ?? []).enumerated() {
                guard let info = strip.info else { continue }
                log("  \(index + 1) \(info.name): knob \(info.knobLabel), switch \(info.switchLabel)")
            }
        default:
            print("Unknown command. Type `help`.")
        }
        return true
    }

    func close() {
        socket?.stop()
        lock.lock()
        defer { lock.unlock() }
        let bytes = driver.stop(hub: &hub)
        try? midi?.send(bytes)
        Thread.sleep(forTimeInterval: 0.1)
        midi?.close()
    }
}

func e16Bridge(_ arguments: ArraySlice<String>) -> Never {
    let session = E16BridgeSession(options: parseE16BridgeOptions(arguments))
    session.connect()
    e16BridgeCurrent = session
    signal(SIGINT) { _ in
        e16BridgeCurrent?.close()
        print("\nRemote Mode left."); flushOutput()
        exit(0)
    }
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

private var e16BridgeCurrent: E16BridgeSession?
