// sbdev e16: probes the OXI E16's Remote Mode (firmware 1.0 and later) on its factory firmware.
//
// Sources: OXI's "E16 REMOTE CONTROL" sheet
// (https://docs.google.com/spreadsheets/d/1Yccnrluv10QL_PauMmtCt64EtYjfSeZEXKrlrw8P24w, the E16 tab,
// gid 1057524829; linked from the firmware 1.2.0 release notes), and the field notes in
// https://github.com/charlesvestal/schwung/blob/main/docs/E16_REMOTE.md (the 8-to-7 packing, "send ENTER
// until the ACK arrives", "send EXIT or it stays blank").
//
// In Remote Mode the host owns the screen and the rings, and the device sends fixed MIDI on channel 1:
// turns as CC 1–16 (clockwise 0x01–0x08, counter-clockwise 0x7F–0x78, with acceleration), encoder
// pushes as notes 0–15, Shift as note 16. SysEx goes to "OXI E16 Port 1" (what the OXI App uses).

import Foundation
import MIDITransport

let e16Usage = """
    Usage:
      sbdev e16 ports                 lists the MIDI ports whose name contains "E16"
      sbdev e16 monitor [--port N]    prints what the E16 sends on Port N (default 1), decoded
      sbdev e16 enter [--port N]      sends ENTER REMOTE MODE and waits 3 s for the ACK
      sbdev e16 exit [--port N]       sends EXIT REMOTE MODE (the device stays blank until it gets one)
      sbdev e16 labels [--port N] <title> [label…]
                                      enters Remote Mode and shows a title (16 characters) and up to
                                      16 labels (4 characters each); leaves Remote Mode on Control-C
      sbdev e16 demo [--port N] [--rate HZ]
                                      enters Remote Mode, shows 16 named channels with colored rings,
                                      and reacts: a turn moves its ring, a push toggles its color,
                                      Shift runs a meter animation on all rings at HZ frames per
                                      second (default 25) for 3 s; leaves Remote Mode on Control-C
    """

// MARK: - The protocol

enum E16Remote {
    static let header: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01]

    /// 8-to-7 packing: per group of up to 7 raw bytes, one byte holding their bit 7s (bit k = byte k),
    /// then the bytes with bit 7 cleared.
    static func pack(_ raw: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < raw.count {
            let group = raw[i..<min(i + 7, raw.count)]
            var msb: UInt8 = 0
            for (k, b) in group.enumerated() where b & 0x80 != 0 { msb |= 1 << UInt8(k) }
            out.append(msb)
            out.append(contentsOf: group.map { $0 & 0x7F })
            i += 7
        }
        return out
    }

    static func message(_ id: [UInt8], _ payload: [UInt8] = []) -> [UInt8] {
        header + id + (payload.isEmpty ? [] : pack(payload)) + [0xF7]
    }

    static let enter = message([0x06, 0x55])
    static let exit = message([0x06, 0x00])
    static let ack: [UInt8] = header + [0x06, 0x53, 0xF7]

    struct Ring {
        var r: UInt8, g: UInt8, b: UInt8   // 0–127 each
        var amount: Double                 // 0…1
        var bipolar = false
    }

    /// LED RING: 7-byte chunks (encoder 0–15, R, G, B, amount MSB, amount LSB, bipolar).
    static func rings(_ rings: [(index: Int, ring: Ring)]) -> [UInt8] {
        var raw: [UInt8] = []
        for (index, ring) in rings {
            let amount = Int((max(0, min(1, ring.amount)) * 16383).rounded())
            raw += [UInt8(index), ring.r & 0x7F, ring.g & 0x7F, ring.b & 0x7F,
                    UInt8((amount >> 7) & 0x7F), UInt8(amount & 0x7F), ring.bipolar ? 1 : 0]
        }
        return message([0x06, 0x04], raw)
    }

    /// LED: 5-byte chunks (encoder 0–15, LED 0–15, R, G, B), for single LEDs of a ring.
    static func leds(_ leds: [(encoder: Int, led: Int, r: UInt8, g: UInt8, b: UInt8)]) -> [UInt8] {
        var raw: [UInt8] = []
        for l in leds { raw += [UInt8(l.encoder), UInt8(l.led), l.r & 0x7F, l.g & 0x7F, l.b & 0x7F] }
        return message([0x06, 0x01], raw)
    }

    /// OLED LABELS: a 16-character title and sixteen 4-character labels, space-padded ASCII.
    static func labels(title: String, labels: [String]) -> [UInt8] {
        var raw = ascii(title, 16)
        for i in 0..<16 { raw += ascii(i < labels.count ? labels[i] : "", 4) }
        return message([0x06, 0x03], raw)
    }

    static func ascii(_ s: String, _ n: Int) -> [UInt8] {
        let bytes = s.unicodeScalars.map { $0.isASCII && $0.value >= 32 && $0.value < 127 ? UInt8($0.value) : 0x3F }
        return Array((bytes + Array(repeating: 0x20, count: n)).prefix(n))
    }

    enum Event {
        case turn(encoder: Int, delta: Int, raw: UInt8)   // encoder 1–16
        case push(encoder: Int, down: Bool)               // encoder 1–16
        case shift(down: Bool)
        case ack
        case other([UInt8])
    }

    static func decode(_ bytes: [UInt8]) -> [Event] {
        if bytes.first == 0xF0 { return [bytes == ack ? .ack : .other(bytes)] }
        var events: [Event] = []
        var i = 0
        while i + 2 < bytes.count {
            let status = bytes[i], d1 = Int(bytes[i + 1]), d2 = bytes[i + 2]
            switch status {
            case 0xB0 where (1...16).contains(d1):
                events.append(.turn(encoder: d1, delta: d2 < 64 ? Int(d2) : Int(d2) - 128, raw: d2))
            case 0x90, 0x80:
                let down = status == 0x90 && d2 > 0
                if d1 == 16 { events.append(.shift(down: down)) }
                else if d1 < 16 { events.append(.push(encoder: d1 + 1, down: down)) }
                else { events.append(.other(Array(bytes[i..<i + 3]))) }
            default:
                events.append(.other(Array(bytes[i..<i + 3])))
            }
            i += 3
        }
        return events
    }
}

func describe(_ event: E16Remote.Event) -> String {
    switch event {
    case .turn(let e, let d, let raw): return "TURN encoder \(e) \(d >= 0 ? "+" : "")\(d) (0x\(String(format: "%02X", raw)))"
    case .push(let e, let down): return "PUSH encoder \(e) \(down ? "down" : "up")"
    case .shift(let down): return "SHIFT \(down ? "down" : "up")"
    case .ack: return "REMOTE MODE ENTERED (ACK)"
    case .other(let b): return "other: " + hex(b)
    }
}

// MARK: - The connection

final class E16Session {
    private(set) var connection: MIDIConnection!
    private let lock = NSLock()
    private var handlers: [([E16Remote.Event]) -> Void] = []
    private var acked = false
    let start = Date()

    init(port: Int, verbose: Bool) throws {
        let name = "OXI E16 Port \(port)"
        connection = try MIDIConnection(clientName: "sbdev e16", sourceName: name, destinationName: name) { [self] bytes in
            let events = E16Remote.decode(bytes)
            lock.lock()
            if events.contains(where: { if case .ack = $0 { return true } else { return false } }) { acked = true }
            let hs = handlers
            lock.unlock()
            if verbose {
                for e in events { print(String(format: "%9.3f  ", Date().timeIntervalSince(start)) + describe(e)) }
                flushOutput()
            }
            for h in hs { h(events) }
        }
    }

    func onEvents(_ handler: @escaping ([E16Remote.Event]) -> Void) {
        lock.lock(); handlers.append(handler); lock.unlock()
    }

    func send(_ bytes: [UInt8]) {
        do { try connection.send(bytes) } catch { fail("send failed: \(error)") }
    }

    /// Sends ENTER every 250 ms until the ACK arrives or `timeout` passes.
    func enter(timeout: TimeInterval = 3) -> Bool {
        lock.lock(); acked = false; lock.unlock()
        let until = Date().addingTimeInterval(timeout)
        var sent = 0
        while Date() < until {
            send(E16Remote.enter); sent += 1
            let step = Date().addingTimeInterval(0.25)
            while Date() < step {
                Thread.sleep(forTimeInterval: 0.02)
                lock.lock(); let ok = acked; lock.unlock()
                if ok { print("ACK after \(sent) ENTER message(s), \(String(format: "%.0f", Date().timeIntervalSince(start) * 1000)) ms"); return true }
            }
        }
        print("No ACK after \(sent) ENTER messages in \(Int(timeout)) s.")
        return false
    }

    func exit() { send(E16Remote.exit) }
}

// MARK: - The commands

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
    var positional: [String] = []
    while let a = rest.first {
        rest.removeFirst()
        switch a {
        case "--port": guard let p = rest.first.flatMap({ Int($0) }) else { fail("--port needs a number") }; rest.removeFirst(); port = p
        case "--rate": guard let r = rest.first.flatMap({ Double($0) }) else { fail("--rate needs a number") }; rest.removeFirst(); rate = r
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
        session.send(E16Remote.labels(title: title, labels: Array(positional.dropFirst())))
        print("Labels sent. Press Control-C to leave Remote Mode."); flushOutput()
        while true { Thread.sleep(forTimeInterval: 60) }

    case "demo":
        e16Demo(session, rate: rate)

    default:
        fail("Unknown e16 command \(command).\n\n\(e16Usage)")
    }
}

private func e16Demo(_ session: E16Session, rate: Double) -> Never {
    installExitOnInterrupt()
    guard session.enter() else { exit(1) }

    // TotalMix FX's eight channel colors, roughly, as the Setup Guide names them.
    let palette: [(UInt8, UInt8, UInt8)] = [
        (127, 0, 0), (127, 60, 0), (127, 110, 0), (0, 110, 0), (0, 90, 110), (0, 0, 127), (90, 0, 110), (90, 90, 90),
    ]
    let names = ["AN 1", "AN 2", "AES", "SPDF", "ADT1", "ADT2", "ADT3", "ADT4",
                 "PB 1", "PB 2", "PB 3", "PB 4", "PB 5", "PB 6", "PB 7", "PB 8"]
    var rings: [E16Remote.Ring] = (0..<16).map {
        let c = palette[$0 % palette.count]
        return E16Remote.Ring(r: c.0, g: c.1, b: c.2, amount: Double($0 + 1) / 17)
    }
    var muted = Array(repeating: false, count: 16)
    let state = NSLock()

    func ringMessage(_ indices: [Int]) -> [UInt8] {
        E16Remote.rings(indices.map { i in
            var r = rings[i]
            if muted[i] { r = E16Remote.Ring(r: 127, g: 20, b: 0, amount: r.amount, bipolar: r.bipolar) }
            return (i, r)
        })
    }

    session.send(E16Remote.labels(title: "TOTALMIX  MAIN", labels: names))
    session.send(ringMessage(Array(0..<16)))
    print("Demo running: turn moves a ring, push toggles mute (orange), Shift runs a meter burst. Control-C leaves Remote Mode.")
    flushOutput()

    session.onEvents { events in
        for e in events {
            switch e {
            case .turn(let encoder, let delta, _):
                state.lock()
                let i = encoder - 1
                rings[i].amount = max(0, min(1, rings[i].amount + Double(delta) / 100))
                let msg = ringMessage([i])
                state.unlock()
                session.send(msg)
            case .push(let encoder, true):
                state.lock()
                muted[encoder - 1].toggle()
                let msg = ringMessage([encoder - 1])
                state.unlock()
                session.send(msg)
            case .shift(true):
                // A meter burst: all 16 rings, `rate` frames per second, for 3 s, then back.
                let frames = Int(3 * rate)
                let t0 = Date()
                for f in 0..<frames {
                    let phase = Double(f) / rate
                    state.lock()
                    let msg = E16Remote.rings((0..<16).map { i in
                        let level = 0.5 + 0.5 * sin(phase * 6 + Double(i) * 0.4)
                        return (i, E16Remote.Ring(r: level > 0.9 ? 127 : 0, g: level > 0.9 ? 0 : 110, b: 0, amount: level))
                    })
                    state.unlock()
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
