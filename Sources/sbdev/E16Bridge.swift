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
                      [--layout 16|4] [--sends A,B] [--no-name-marks] [--left] [--meters] [--peak-hold S] [--meter-average S] [--meter-offset DB] [--pan-center A,B,C…] [--pan-leave 1,0…] [--pan-pause S] [--jump-pause S] [--verbose]
          Connects TotalMix FX and an OXI E16 (in its Remote Mode) through SurfaceCore and the E16
          driver, as the app does. Prints what is sent to TotalMix FX, with the time since
          starting; --verbose also prints every MIDI message to and from the device. Then reads
          commands from the keyboard (type `help`).
          --port names the device's first USB port (default "OXI E16 Port 1").
          --host, --in-port, and --out-port are TotalMix FX's, as for monitor. --home is the home
          submix's output number, counting from 1 (default: TotalMix FX's Main Out).
          --layout 4 is the 4-channel layout (default 16). --sends A,B are its send rows' outputs,
          counting from 1 (default: the first two send targets). --no-name-marks turns off the
          trial of inverted names for a mute and a square after the name for a PFL. --left puts
          the labels at the left of their cells (default: centered). --meters shows each
          channel's level as a bar under its name (TotalMix FX's "Send Level Data" must be on,
          its "Peak Hold" off), with a pixel holding the peak for S seconds (--peak-hold; default 2);
          the bar averages the peaks with a time constant of S seconds (--meter-average; default
          0.03) and sits DB below them (--meter-offset; default 6).
          --pan-center gives the pans' sticky center a different number of units per encoder, to
          compare them side by side: with 2,5,10, encoders 1, 4, 7… take 2, encoders 2, 5, 8…
          take 5, and encoders 3, 6, 9… take 10 (default: the driver's 2 on every encoder).
          --pan-leave, the same way, sets how a pan leaves center per encoder: 1 moves it one step
          (the driver's way), 0 carries the units beyond the count.
          --pan-pause is how long, in seconds, a turn that stopped at center must pause before
          turning moves on (default 0.05).
          --jump-pause is how long, in seconds, push-and-turn must pause after a jump before it
          jumps again (default 0.075).
          Stop sbdev monitor, the other bridges, and the app first: they need the same ports.

      On the device: turn is level, pan, or a send, by the mode; push and release is mute; a hold of
      one second is PFL; with Shift held the encoders are buttons: 1 LEVEL, 2 PAN, 3 SEND, 11 and 12
      the previous and next send output, 13 and 14 the layout, 15 and 16 the previous and next page.
      Control-C or `quit`
      gives the device back.

      In the 4-channel layout: four channels across, one column each; the rows turn send A, send
      B, pan, and level. A push on any encoder of a column is mute, a hold of one second PFL. With
      Shift held: 3 and 4 the previous and next output for send A, 7 and 8 for send B, 13 and 14
      the layout, 15 and 16 the previous and next page.
    """

let e16BridgeCommandHelp = """
    Commands:
      home N | home main   the home submix: output N (from 1), or TotalMix FX's Main Out
      pbpage on | pbpage off   start the first playback on a new page, or not
      sendall              ask TotalMix FX for its state again
      peaks                the highest level TotalMix FX sent for each channel on the page since the
                           last `peaks`, to compare with TotalMix FX's peak readouts
      status               the function, the home submix, the send targets, and the strips
      brightness N         the rings' brightness as the app's slider reads it, 1–100
      floor N              the least a Shift-page button in use is lit at the top of its pulse
                           (its color's largest part, 0–127; the driver's default is 8)
      pulse S              how long one pulse of a Shift-page button in use takes, in seconds
                           (0 holds it steady; the driver's default is 1)
      top F                the top of that pulse as a share of the brightness, 0–1 (never below
                           the floor; the driver's default is 1)
      quit                 leave Remote Mode and stop
    """

struct E16BridgeOptions {
    var endpoint = TotalMixEndpoint.standard
    var portName = "OXI E16 Port 1"
    var home: Int?
    var panCenter: [Int] = []
    var panLeave: [Bool] = []
    var panPause: Double?
    var jumpPause: Double?
    var layout = E16Driver.Layout.sixteen
    var sends: [Int?] = []
    var nameMarks = true
    var left = false
    var meters = false
    var peakHold: Double?
    var meterAverage: Double?
    var meterOffset: Double?
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
        case "--pan-leave":
            let ways = value(argument).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !ways.isEmpty, ways.allSatisfy({ $0 == "0" || $0 == "1" }) else { fail("--pan-leave needs 1s and 0s, separated by commas.") }
            options.panLeave = ways.map { $0 == "1" }
        case "--layout":
            switch value(argument) {
            case "16": options.layout = .sixteen
            case "4": options.layout = .four
            default: fail("--layout needs 16 or 4.")
            }
        case "--sends":
            let outputs = value(argument).split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard (1...2).contains(outputs.count), outputs.allSatisfy({ ($0 ?? 0) >= 1 }) else { fail("--sends needs one or two output numbers from 1, separated by a comma.") }
            options.sends = outputs.map { $0.map { $0 - 1 } }
        case "--no-name-marks": options.nameMarks = false
        case "--left": options.left = true
        case "--meters": options.meters = true
        case "--peak-hold":
            guard let seconds = Double(value(argument)), seconds >= 0, seconds.isFinite else { fail("--peak-hold needs seconds from 0.") }
            options.peakHold = seconds
        case "--meter-average":
            guard let seconds = Double(value(argument)), seconds >= 0, seconds.isFinite else { fail("--meter-average needs seconds from 0.") }
            options.meterAverage = seconds
        case "--meter-offset":
            guard let db = Double(value(argument)), db >= 0, db.isFinite else { fail("--meter-offset needs dB from 0.") }
            options.meterOffset = db
        case "--pan-pause":
            guard let seconds = Double(value(argument)), seconds >= 0, seconds.isFinite else { fail("--pan-pause needs seconds from 0.") }
            options.panPause = seconds
        case "--jump-pause":
            guard let seconds = Double(value(argument)), seconds >= 0, seconds.isFinite else { fail("--jump-pause needs seconds from 0.") }
            options.jumpPause = seconds
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
    private var driver: E16Driver
    private var socket: UDPSocket?
    private var midi: MIDIConnection?
    private var wasConnected = false

    init(options: E16BridgeOptions) {
        self.options = options
        driver = E16Driver(name: "e16", layout: options.layout, sendOutputs: options.sends)
        driver.marksNames = options.nameMarks
        driver.centersLabels = !options.left
        driver.showsMeters = options.meters
        if let hold = options.peakHold { driver.peakHold = hold }
        if let average = options.meterAverage { driver.meterAverage = average }
        if let offset = options.meterOffset { driver.meterOffset = offset }
        driver.panCenterTrial = options.panCenter
        driver.panLeaveTrial = options.panLeave
        if let pause = options.panPause { driver.panCenterPause = pause }
        if let pause = options.jumpPause { driver.jumpPause = pause }
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

    /// The highest level TotalMix FX has sent for each channel since the last `peaks` command.
    private var levelMaxima: [ChannelRef: Double] = [:]

    private func fromTotalMix(_ bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        guard let packet = try? OSCPacket(decoding: bytes) else { return }
        for message in packet.messages {
            guard let event = TotalMixEvent(message) else { continue }
            if case .level(let bus, let channel, let peak) = event {
                let ref = ChannelRef(bus, channel)
                levelMaxima[ref] = max(levelMaxima[ref] ?? -.infinity, peak)
            }
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
        case "peaks":
            // The highest level TotalMix FX sent for each channel on the page since the last
            // `peaks`, to compare with TotalMix FX's own peak readouts (Adam, 2026-11-06).
            for strip in hub.strips(of: driver.id(driver.layout == .four ? .level : .main)) ?? [] {
                guard let info = strip.info else { continue }
                var refs = [info.channel]
                if info.stereo { refs.append(ChannelRef(info.channel.bus, info.channel.channel + 1)) }
                let text = refs.map { levelMaxima[$0].map { String(format: "%.1f", $0) } ?? "none" }.joined(separator: " / ")
                log("  \(info.name): highest sent \(text) dB")
            }
            levelMaxima = [:]
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
        case "brightness":
            guard words.count == 2, let shown = Double(words[1]), (1...100).contains(shown) else {
                print("brightness N, from 1 to 100")
                return true
            }
            // The app's slider: 1–100 for 3%–80% of the LEDs' output (BridgeEngine's range).
            let bytes = driver.setBrightness(0.03 + (shown - 1) / 99 * 0.77, hub: hub)
            try? midi?.send(bytes)
            log("Brightness \(Int(shown))")
        case "floor":
            guard words.count == 2, let level = Double(words[1]), (0...127).contains(level) else {
                print("floor N, from 0 to 127")
                return true
            }
            driver.inUseFloor = level
            let bytes = driver.setBrightness(driver.brightness, hub: hub)  // redraws every ring
            try? midi?.send(bytes)
            log("In-use floor \(Int(level))")
        case "pulse":
            guard words.count == 2, let seconds = Double(words[1]), seconds >= 0, seconds.isFinite else {
                print("pulse S, in seconds from 0")
                return true
            }
            driver.pulsePeriod = seconds
            log("Pulse \(seconds) s")
        case "top":
            guard words.count == 2, let share = Double(words[1]), (0...1).contains(share) else {
                print("top F, from 0 to 1")
                return true
            }
            driver.pulseTop = share
            log("Pulse top \(share)")
        case "status":
            log("Connected: \(driver.isConnected); function: \(driver.function); title: \"\(driver.title(hub: hub))\"")
            log("Home submix: \(hub.homeSubmix.map { "output \($0 + 1)" } ?? "none yet"); send targets: \(hub.sendTargets.map { "output \($0 + 1)" })")
            if driver.layout == .four {
                log("Send rows: \(driver.currentSendOutputs(hub: hub).map { $0.map { "output \($0 + 1)" } ?? "none" })")
            }
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
