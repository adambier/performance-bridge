// The OXI E16's Remote Mode: the messages a host sends to take over the device's screen and LED
// rings, and the MIDI the device sends back while the host has it. Foundation only.
//
// Sources: OXI's "E16 REMOTE CONTROL" sheet (the E16 tab of the Google Sheet linked from the
// firmware 1.2.0 release notes; docs/OXI-E16.md, section 3), and this project's own tests on
// firmware 1.3.0 (docs/OXI-E16.md, section 7).

import Foundation

/// One ring's look: a color (0–127 per part) and how much of it is lit.
public struct E16Ring: Hashable, Sendable {
    /// Red, 0–127.
    public var red: UInt8
    /// Green, 0–127.
    public var green: UInt8
    /// Blue, 0–127.
    public var blue: UInt8
    /// How much of the ring is lit, 0…1 (sent as a 14-bit value, 0–16383).
    public var amount: Double
    /// Whether the ring fills from the center outward (a pan) rather than from the start (an
    /// arc).
    public var bipolar: Bool

    /// A ring.
    public init(red: UInt8, green: UInt8, blue: UInt8, amount: Double, bipolar: Bool = false) {
        self.red = red
        self.green = green
        self.blue = blue
        self.amount = amount
        self.bipolar = bipolar
    }

    /// A dark ring.
    public static let off = E16Ring(red: 0, green: 0, blue: 0, amount: 0)

    /// The 14-bit amount sent, 0–16383.
    public var amount14: Int {
        guard amount.isFinite else { return 0 }
        return Int((min(max(amount, 0), 1) * 16383).rounded())
    }
}

/// The messages a host sends to an E16 in Remote Mode, as complete SysEx messages.
public enum E16Outgoing {
    /// OXI's SysEx header for the E16: `F0 00 21 5B 02 01`.
    public static let header: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01]

    /// The number of encoders.
    public static let encoderCount = 16
    /// The length of the screen's title, in characters.
    public static let titleLength = 16
    /// The length of each encoder's label, in characters.
    public static let labelLength = 4

    /// 8-to-7 packing: for each group of up to 7 raw bytes, one byte holding their bit 7s (bit k
    /// for byte k of the group), then the bytes with bit 7 cleared.
    public static func pack(_ raw: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(raw.count + raw.count / 7 + 1)
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

    /// The inverse of `pack(_:)`: the raw bytes of a packed payload. Bytes with bit 7 set, which
    /// a device never sends, are taken as they are.
    public static func unpack(_ packed: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < packed.count {
            let msb = packed[i]
            let group = packed[(i + 1)..<min(i + 8, packed.count)]
            for (k, b) in group.enumerated() { out.append(b | (msb & (1 << UInt8(k)) != 0 ? 0x80 : 0)) }
            i += 8
        }
        return out
    }

    /// A complete message: the header, a message ID, the packed payload (if any), and `F7`.
    public static func message(_ id: [UInt8], payload: [UInt8] = []) -> [UInt8] {
        header + id + (payload.isEmpty ? [] : pack(payload)) + [0xF7]
    }

    /// ENTER REMOTE MODE (`06 55`): the device answers with `E16Event.remoteEntered` and blanks its
    /// screen and rings.
    public static let enterRemoteMode = message([0x06, 0x55])
    /// EXIT REMOTE MODE (`06 00`): the device shows its own scene again.
    public static let exitRemoteMode = message([0x06, 0x00])

    /// LED RING (`06 04`): the rings of the given encoders (0–15), each as a 7-byte chunk (index,
    /// R, G, B, amount MSB, amount LSB, bipolar). Encoders out of range are left out.
    public static func rings(_ rings: [(encoder: Int, ring: E16Ring)]) -> [UInt8] {
        var raw: [UInt8] = []
        for (encoder, ring) in rings where (0..<encoderCount).contains(encoder) {
            let amount = ring.amount14
            raw += [UInt8(encoder), ring.red & 0x7F, ring.green & 0x7F, ring.blue & 0x7F,
                    UInt8((amount >> 7) & 0x7F), UInt8(amount & 0x7F), ring.bipolar ? 1 : 0]
        }
        return raw.isEmpty ? [] : message([0x06, 0x04], payload: raw)
    }

    /// The most LEDs one LED message carries: sixteen, the most tested on the device (test 5 of
    /// `docs/OXI-E16.md`); more go in further messages.
    public static let ledsPerMessage = 16

    /// LED (`06 01`): single LEDs (0–15) of encoders (0–15), each as a 5-byte chunk (encoder, LED,
    /// R, G, B), at most `ledsPerMessage` to a message. Out-of-range entries are left out.
    public static func leds(_ leds: [(encoder: Int, led: Int, red: UInt8, green: UInt8, blue: UInt8)]) -> [UInt8] {
        let valid = leds.filter { (0..<encoderCount).contains($0.encoder) && (0..<16).contains($0.led) }
        var out: [UInt8] = []
        for start in stride(from: 0, to: valid.count, by: ledsPerMessage) {
            var raw: [UInt8] = []
            for l in valid[start..<min(start + ledsPerMessage, valid.count)] {
                raw += [UInt8(l.encoder), UInt8(l.led), l.red & 0x7F, l.green & 0x7F, l.blue & 0x7F]
            }
            out += message([0x06, 0x01], payload: raw)
        }
        return out
    }

    /// OLED LABELS (`06 03`): a title of `titleLength` characters and `encoderCount` labels of
    /// `labelLength` characters each, in the device's own knob layout. Text is cut, or padded
    /// with null bytes (the sheet allows spaces or nulls; with spaces the device centered the
    /// title with its padding, so a short title sat off center; Adam, 2026-11-04); characters
    /// outside printable ASCII become `?`.
    public static func labels(title: String, labels: [String]) -> [UInt8] {
        var raw = ascii(title, titleLength)
        for i in 0..<encoderCount { raw += ascii(i < labels.count ? labels[i] : "", labelLength) }
        return message([0x06, 0x03], payload: raw)
    }

    /// `text` as `length` bytes of printable ASCII, cut or padded with null bytes.
    public static func ascii(_ text: String, _ length: Int) -> [UInt8] {
        let bytes = text.unicodeScalars.map { scalar -> UInt8 in
            scalar.isASCII && scalar.value >= 32 && scalar.value < 127 ? UInt8(scalar.value) : 0x3F
        }
        return Array((bytes + Array(repeating: 0x00, count: length)).prefix(length))
    }
}

/// What an E16 sends in Remote Mode, decoded.
public enum E16Event: Hashable, Sendable {
    /// REMOTE MODE ENTERED (`06 53`): the device is the host's.
    case remoteEntered
    /// An encoder (0–15) turned: `delta` is positive clockwise, from the device's own
    /// acceleration (1–8 a message either way).
    case turned(encoder: Int, delta: Int)
    /// An encoder (0–15) was pressed (`down` true) or released.
    case pushed(encoder: Int, down: Bool)
    /// The Shift button went down or up.
    case shift(down: Bool)
    /// A SysEx message from the device that isn't the ACK, without its `F0` and `F7`.
    case sysEx([UInt8])
    /// Any other channel message, as its bytes.
    case other([UInt8])
}

/// Turns the bytes an E16 sends in Remote Mode into events. SysEx may arrive in pieces; the
/// parser keeps what it has until the `F7`.
public struct E16Parser: Sendable {
    private var sysEx: [UInt8]?
    private var pending: [UInt8] = []

    /// A parser.
    public init() {}

    /// Feeds bytes as they arrive and returns the events completed by them.
    public mutating func feed<S: Sequence>(_ bytes: S) -> [E16Event] where S.Element == UInt8 {
        var events: [E16Event] = []
        for byte in bytes {
            if var body = sysEx {
                if byte == 0xF7 {
                    sysEx = nil
                    events.append(Self.decodeSysEx(body))
                } else if byte >= 0xF8 {
                    // A real-time byte may arrive inside SysEx (MIDI 1.0); it is not part of it.
                    continue
                } else if byte & 0x80 != 0 {
                    // A status byte inside SysEx: the message was cut short. Start over.
                    sysEx = nil
                    pending = []
                    if byte == 0xF0 { sysEx = [] } else { pending = [byte] }
                } else {
                    body.append(byte)
                    sysEx = body
                }
                continue
            }
            if byte == 0xF0 { sysEx = []; pending = []; continue }
            if byte >= 0xF8 { continue }  // real-time
            if byte & 0x80 != 0 { pending = [byte]; continue }
            pending.append(byte)
            if pending.count == 3 {
                events.append(Self.decodeChannel(pending))
                pending = [pending[0]]  // running status
            }
        }
        return events
    }

    private static func decodeSysEx(_ body: [UInt8]) -> E16Event {
        let header = Array(E16Outgoing.header.dropFirst())
        if body.count == header.count + 2, Array(body.prefix(header.count)) == header,
           body[header.count] == 0x06, body[header.count + 1] == 0x53 {
            return .remoteEntered
        }
        return .sysEx(body)
    }

    private static func decodeChannel(_ bytes: [UInt8]) -> E16Event {
        let status = bytes[0], d1 = Int(bytes[1]), d2 = Int(bytes[2])
        switch status {
        case 0xB0 where (1...16).contains(d1):
            return .turned(encoder: d1 - 1, delta: d2 < 64 ? d2 : d2 - 128)
        case 0x90, 0x80:
            let down = status == 0x90 && d2 > 0
            if d1 == 16 { return .shift(down: down) }
            if d1 < 16 { return .pushed(encoder: d1, down: down) }
            return .other(bytes)
        default:
            return .other(bytes)
        }
    }
}
