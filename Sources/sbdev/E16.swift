// sbdev e16: probes the OXI E16's Remote Mode (firmware 1.3.0 and later) on its factory firmware,
// through the OXIE16 library. Tested on firmware 1.3.0 (Adam, 2026-11-04; docs/OXI-E16.md).

import Foundation
import MIDITransport
import OXIE16
import E16Driver

let e16Usage = """
    Usage:
      sbdev e16 ports                 lists the MIDI ports whose name contains "E16"
      sbdev e16 monitor [--port N]    prints what the E16 sends on Port N (default 1), decoded
      sbdev e16 enter [--port N]      sends ENTER REMOTE MODE and waits 3 s for the ACK
      sbdev e16 exit [--port N]       sends EXIT REMOTE MODE (the device stays blank until it gets one)
      sbdev e16 labels [--port N] <title> [label…]
                                      enters Remote Mode and shows a title (16 characters) and up to
                                      16 labels (4 characters each); leaves Remote Mode on Control-C
      sbdev e16 palette [--port N]    enters Remote Mode and shows candidate colors, one per ring,
                                      full, named on the screen (TotalMix FX's own first); leaves
                                      Remote Mode on Control-C
      sbdev e16 colors [--port N] [--brightness B] [--rgb R,G,B …]
                                      enters Remote Mode and shows the driver's colors, full rings,
                                      named on the screen, dimmed as the driver dims them at
                                      brightness B (0…1; default 0.10, the slider's 1): rows 1–2
                                      TotalMix FX's colors as the driver maps them, row 3 mute,
                                      PFL, and the Shift buttons, row 4 up to four --rgb trials;
                                      leaves Remote Mode on Control-C
      sbdev e16 ramp [--port N]       enters Remote Mode and shows white rings at 16 brightness
                                      values from 1 to 127, labeled; leaves Remote Mode on Control-C
      sbdev e16 demo [--port N] [--rate HZ]
                                      enters Remote Mode, shows 16 named channels with colored rings,
                                      and reacts: a turn moves its ring, a push toggles its color,
                                      Shift runs a meter animation on all rings at HZ frames per
                                      second (default 25) for 3 s; leaves Remote Mode on Control-C
    """

func describe(_ event: E16Event) -> String {
    switch event {
    case .turned(let e, let d): return "TURN encoder \(e + 1) \(d >= 0 ? "+" : "")\(d)"
    case .pushed(let e, let down): return "PUSH encoder \(e + 1) \(down ? "down" : "up")"
    case .shift(let down): return "SHIFT \(down ? "down" : "up")"
    case .remoteEntered: return "REMOTE MODE ENTERED (ACK)"
    case .sysEx(let b): return "SysEx: F0 " + hex(b) + " F7"
    case .other(let b): return "other: " + hex(b)
    }
}

/// The E16's first USB port, with the ACK watched for.
final class E16Session {
    private(set) var connection: MIDIConnection!
    private let lock = NSLock()
    private var parser = E16Parser()
    private var handlers: [([E16Event]) -> Void] = []
    private var ackedAt: Date?
    let start = Date()

    init(port: Int, verbose: Bool) throws {
        let name = "OXI E16 Port \(port)"
        connection = try MIDIConnection(clientName: "sbdev e16", sourceName: name, destinationName: name) { [self] bytes in
            lock.lock()
            let events = parser.feed(bytes)
            if events.contains(.remoteEntered) { ackedAt = Date() }
            let hs = handlers
            lock.unlock()
            if verbose {
                for e in events { print(String(format: "%9.3f  ", Date().timeIntervalSince(start)) + describe(e)) }
                flushOutput()
            }
            for h in hs { h(events) }
        }
    }

    func onEvents(_ handler: @escaping ([E16Event]) -> Void) {
        lock.lock(); handlers.append(handler); lock.unlock()
    }

    func send(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        do { try connection.send(bytes) } catch { fail("send failed: \(error)") }
    }

    /// Sends ENTER every 250 ms until the ACK arrives or `timeout` passes, and reports the time
    /// from the last ENTER to the ACK as the receive callback saw it. (An earlier version
    /// reported the time since the tool started, polled every 20 ms: the "42 ms" in the first
    /// probe; review of 2026-11-04.)
    func enter(timeout: TimeInterval = 3) -> Bool {
        lock.lock(); ackedAt = nil; lock.unlock()
        let until = Date().addingTimeInterval(timeout)
        var sent = 0
        while Date() < until {
            let sentAt = Date()
            send(E16Outgoing.enterRemoteMode); sent += 1
            let step = Date().addingTimeInterval(0.25)
            while Date() < step {
                Thread.sleep(forTimeInterval: 0.005)
                lock.lock(); let at = ackedAt; lock.unlock()
                if let at { print("ACK after \(sent) ENTER message(s), \(String(format: "%.1f", at.timeIntervalSince(sentAt) * 1000)) ms after the last"); return true }
            }
        }
        print("No ACK after \(sent) ENTER messages in \(Int(timeout)) s.")
        return false
    }

    func exit() { send(E16Outgoing.exitRemoteMode) }
}

private var e16Current: E16Session?

private func installExitOnInterrupt() {
    signal(SIGINT) { _ in
        e16Current?.exit()
        Thread.sleep(forTimeInterval: 0.1)
        print("\nEXIT sent."); flushOutput()
        exit(0)
    }
}

func e16(_ arguments: ArraySlice<String>) -> Never {
    var rest = Array(arguments)
    guard let command = rest.first else { print(e16Usage); exit(0) }
    rest.removeFirst()
    var port = 1
    var rate = 25.0
    var brightness = 0.10
    var trials: [(UInt8, UInt8, UInt8)] = []
    var positional: [String] = []
    while let a = rest.first {
        rest.removeFirst()
        switch a {
        case "--port": guard let p = rest.first.flatMap({ Int($0) }) else { fail("--port needs a number") }; rest.removeFirst(); port = p
        case "--rate": guard let r = rest.first.flatMap({ Double($0) }) else { fail("--rate needs a number") }; rest.removeFirst(); rate = r
        case "--brightness": guard let b = rest.first.flatMap({ Double($0) }) else { fail("--brightness needs a number from 0 to 1") }; rest.removeFirst(); brightness = b
        case "--rgb":
            let parts = rest.first?.split(separator: ",").compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) } ?? []
            guard parts.count == 3, parts.allSatisfy({ $0 <= 127 }) else { fail("--rgb needs R,G,B, each 0–127") }
            rest.removeFirst(); trials.append((parts[0], parts[1], parts[2]))
        case "-h", "--help": print(e16Usage); exit(0)
        default: positional.append(a)
        }
    }

    if command == "ports" {
        print("Sources:"); for s in MIDIConnection.sources() where s.name.contains("E16") { print("  \(s.name)") }
        print("Destinations:"); for d in MIDIConnection.destinations() where d.name.contains("E16") { print("  \(d.name)") }
        exit(0)
    }

    let session: E16Session
    do { session = try E16Session(port: port, verbose: true) } catch { fail("\(error)") }
    e16Current = session
    print("Using \"\(session.connection.source.name)\".")

    switch command {
    case "monitor":
        print("Listening. Press Control-C to stop."); flushOutput()
        while true { Thread.sleep(forTimeInterval: 60) }

    case "enter":
        _ = session.enter(); exit(0)

    case "exit":
        session.exit(); Thread.sleep(forTimeInterval: 0.2); print("EXIT sent."); exit(0)

    case "labels":
        guard let title = positional.first else { fail("labels needs a title.\n\n\(e16Usage)") }
        installExitOnInterrupt()
        guard session.enter() else { exit(1) }
        session.send(E16Outgoing.labels(title: title, labels: Array(positional.dropFirst())))
        print("Labels sent. Press Control-C to leave Remote Mode."); flushOutput()
        while true { Thread.sleep(forTimeInterval: 60) }

    case "demo":
        e16Demo(session, rate: rate)

    case "ramp":
        installExitOnInterrupt()
        guard session.enter() else { exit(1) }
        let values: [UInt8] = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 80, 96, 112, 127]
        session.send(E16Outgoing.labels(title: "BRIGHTNESS", labels: values.map { String($0) }))
        session.send(E16Outgoing.rings(values.enumerated().map { (i, v) in
            (encoder: i, ring: E16Ring(red: v, green: v, blue: v, amount: 1))
        }))
        print("White rings at 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 80, 96, 112, 127. Control-C leaves Remote Mode."); flushOutput()
        while true { Thread.sleep(forTimeInterval: 60) }

    case "colors":
        installExitOnInterrupt()
        guard session.enter() else { exit(1) }
        let tm = E16Driver.totalMixRGB
        var colors: [(String, (UInt8, UInt8, UInt8))] = [
            ("WHIT", tm[1]!), ("GREY", tm[2]!), ("ORNG", tm[3]!), ("RED", tm[4]!),
            ("BLUE", tm[5]!), ("GREN", tm[6]!), ("YELO", tm[7]!), ("PURP", tm[8]!),
            ("MUTE", E16Driver.muteRGB), ("PFL", E16Driver.pflRGB),
            ("LVL", E16Driver.buttonColors.level), ("PAN", E16Driver.buttonColors.pan),
            ("SEND", E16Driver.buttonColors.send), ("PAGE", E16Driver.buttonColors.page),
        ]
        for (i, t) in trials.prefix(4).enumerated() { colors.append(("T\(i + 1)", t)) }
        while colors.count < 16 { colors.append(("", (0, 0, 0))) }
        let percent = Int((brightness * 100).rounded())
        session.send(E16Outgoing.labels(title: "COLORS \(percent)%", labels: colors.map { $0.0 }))
        session.send(E16Outgoing.rings(colors.enumerated().map { (i, c) in
            let rgb = E16Driver.scaled(c.1, brightness: brightness)
            return (encoder: i, ring: E16Ring(red: rgb.0, green: rgb.1, blue: rgb.2, amount: c.0.isEmpty ? 0 : 1))
        }))
        for (i, c) in colors.enumerated() where !c.0.isEmpty {
            let d = E16Driver.scaled(c.1, brightness: brightness)
            print(String(format: "%2d %-4@  full (%3d,%3d,%3d)  sent (%3d,%3d,%3d)", i + 1, c.0 as NSString, Int(c.1.0), Int(c.1.1), Int(c.1.2), Int(d.0), Int(d.1), Int(d.2)))
        }
        print("At brightness \(percent)%, as the driver dims. Control-C leaves Remote Mode."); flushOutput()
        while true { Thread.sleep(forTimeInterval: 60) }

    case "palette":
        installExitOnInterrupt()
        guard session.enter() else { exit(1) }
        // TotalMix FX's colors as the driver renders them, then candidates for its grey.
        let colors: [(String, UInt8, UInt8, UInt8)] = [
            ("WHIT", 127, 127, 127), ("BLUE", 0, 0, 127), ("GREN", 0, 127, 0), ("PURP", 90, 0, 127),
            ("ORNG", 127, 40, 0), ("YELO", 127, 85, 0), ("RED", 127, 0, 0), ("", 0, 0, 0),
            ("STEL", 50, 85, 127), ("ICE", 90, 110, 127), ("SLAT", 70, 80, 110), ("CYAN", 0, 110, 127),
            ("TEAL", 0, 127, 110), ("MINT", 60, 127, 90), ("LILC", 100, 90, 127), ("GRAY", 40, 40, 40),
        ]
        session.send(E16Outgoing.labels(title: "TM / GREY TRIALS", labels: colors.map { $0.0 }))
        session.send(E16Outgoing.rings(colors.enumerated().map { (i, c) in
            (encoder: i, ring: E16Ring(red: c.1, green: c.2, blue: c.3, amount: c.0.isEmpty ? 0 : 1))
        }))
        print("Rows 1–2: TotalMix FX's colors. Rows 3–4: candidates for grey. Control-C leaves Remote Mode."); flushOutput()
        while true { Thread.sleep(forTimeInterval: 60) }

    default:
        fail("Unknown e16 command \(command).\n\n\(e16Usage)")
    }
}

private func e16Demo(_ session: E16Session, rate: Double) -> Never {
    installExitOnInterrupt()
    guard session.enter() else { exit(1) }

    let palette: [(UInt8, UInt8, UInt8)] = [
        (127, 0, 0), (127, 60, 0), (127, 110, 0), (0, 110, 0), (0, 90, 110), (0, 0, 127), (90, 0, 110), (90, 90, 90),
    ]
    let names = ["AN 1", "AN 2", "AES", "SPDF", "ADT1", "ADT2", "ADT3", "ADT4",
                 "PB 1", "PB 2", "PB 3", "PB 4", "PB 5", "PB 6", "PB 7", "PB 8"]
    var rings: [E16Ring] = (0..<16).map {
        let c = palette[$0 % palette.count]
        return E16Ring(red: c.0, green: c.1, blue: c.2, amount: Double($0 + 1) / 17)
    }
    var muted = Array(repeating: false, count: 16)
    let state = NSLock()

    func ringMessage(_ indices: [Int]) -> [UInt8] {
        E16Outgoing.rings(indices.map { i in
            var r = rings[i]
            if muted[i] { r = E16Ring(red: 127, green: 20, blue: 0, amount: r.amount, bipolar: r.bipolar) }
            return (encoder: i, ring: r)
        })
    }

    session.send(E16Outgoing.labels(title: "TOTALMIX  MAIN", labels: names))
    session.send(ringMessage(Array(0..<16)))
    print("Demo running: turn moves a ring, push toggles mute (orange), Shift runs a meter burst. Control-C leaves Remote Mode.")
    flushOutput()

    session.onEvents { events in
        for e in events {
            switch e {
            case .turned(let i, let delta):
                state.lock()
                rings[i].amount = max(0, min(1, rings[i].amount + Double(delta) / 100))
                let msg = ringMessage([i])
                state.unlock()
                session.send(msg)
            case .pushed(let i, true):
                state.lock()
                muted[i].toggle()
                let msg = ringMessage([i])
                state.unlock()
                session.send(msg)
            case .shift(true):
                let frames = Int(3 * rate)
                let t0 = Date()
                for f in 0..<frames {
                    let phase = Double(f) / rate
                    let msg = E16Outgoing.rings((0..<16).map { i in
                        let level = 0.5 + 0.5 * sin(phase * 6 + Double(i) * 0.4)
                        return (encoder: i, ring: E16Ring(red: level > 0.9 ? 127 : 0, green: level > 0.9 ? 0 : 110, blue: 0, amount: level))
                    })
                    session.send(msg)
                    Thread.sleep(forTimeInterval: 1 / rate)
                }
                let ms = Date().timeIntervalSince(t0) * 1000
                print(String(format: "meter burst: %d frames of 16 rings in %.0f ms (%.1f fps)", frames, ms, Double(frames) / ms * 1000))
                state.lock(); let msg = ringMessage(Array(0..<16)); state.unlock()
                session.send(msg)
            default: break
            }
        }
    }
    while true { Thread.sleep(forTimeInterval: 60) }
}
