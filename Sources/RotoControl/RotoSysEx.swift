import Foundation

/// The framing and value encodings of the Roto-Control's SysEx messages (docs/ROTO-CONTROL.md,
/// section 2).
public enum RotoSysEx {
    /// Melbourne Instruments' SysEx manufacturer ID.
    public static let manufacturerID: [UInt8] = [0x00, 0x22, 0x03]
    /// The Roto-Control's device ID.
    public static let deviceID: UInt8 = 0x02
    /// The bytes every Roto-Control SysEx message starts with, from `F0` through the device ID.
    public static let header: [UInt8] = [0xF0] + manufacturerID + [deviceID]
    /// The length of a name field: 12 characters and a terminating 0 byte.
    public static let nameFieldLength = 13
    /// The largest two-byte number: 14 bits.
    public static let maximum14Bit = 0x3FFF

    /// A complete message: header, group, command, data, and `F7`. Data bytes are masked to 7 bits.
    public static func frame(_ group: RotoCommandGroup, _ command: UInt8, _ data: [UInt8] = []) -> [UInt8] {
        header + [group.rawValue, command & 0x7F] + data.map { $0 & 0x7F } + [0xF7]
    }

    /// The group, command, and data of a Roto-Control SysEx message, or `nil` if the bytes are not
    /// one (wrong header, no `F7`, or too short).
    public static func unframe(_ bytes: [UInt8]) -> (group: UInt8, command: UInt8, data: [UInt8])? {
        guard bytes.count >= header.count + 3,
              Array(bytes.prefix(header.count)) == header,
              bytes.last == 0xF7 else { return nil }
        let group = bytes[header.count]
        let command = bytes[header.count + 1]
        let data = Array(bytes[(header.count + 2)..<(bytes.count - 1)])
        return (group, command, data)
    }

    /// A number as two 7-bit bytes, high bits first; clamped to 0…16383.
    public static func encode14(_ value: Int) -> [UInt8] {
        let clamped = min(max(value, 0), maximum14Bit)
        return [UInt8(clamped >> 7), UInt8(clamped & 0x7F)]
    }

    /// The number held in two 7-bit bytes, high bits first.
    public static func decode14(_ high: UInt8, _ low: UInt8) -> Int {
        Int(high & 0x7F) << 7 | Int(low & 0x7F)
    }

    /// An RGB component (0–255) as two bytes: bit 7, then the low seven bits. Logic's integration
    /// encodes colors this way (docs/ROTO-CONTROL.md, section 2).
    public static func encodeColorComponent(_ value: UInt8) -> [UInt8] {
        [value >> 7, value & 0x7F]
    }

    /// A name as a 13-byte field: at most 12 characters, then 0 bytes. Characters outside
    /// printable ASCII become `?` (this project's choice; the SysEx doc says only "ASCII").
    public static func encodeName(_ name: String) -> [UInt8] {
        let ascii = name.unicodeScalars.prefix(nameFieldLength - 1).map { scalar -> UInt8 in
            (0x20...0x7E).contains(scalar.value) ? UInt8(scalar.value) : UInt8(ascii: "?")
        }
        return ascii + [UInt8](repeating: 0, count: nameFieldLength - ascii.count)
    }

    /// The text of a name field, up to its first 0 byte.
    public static func decodeName<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        String(decoding: bytes.prefix { $0 != 0 }.map { $0 & 0x7F }, as: UTF8.self)
    }
}

/// The three groups of SysEx commands.
public enum RotoCommandGroup: UInt8, Sendable {
    /// General commands (`0A`): the handshake, tracks, and transport.
    case general = 0x0A
    /// PLUGIN mode (`0B`). Performance Bridge does not use it.
    case plugin = 0x0B
    /// MIX mode (`0C`).
    case mix = 0x0C
}

/// The DAW a host claims to be in DAW PING RESPONSE. The SysEx doc defines no other type
/// (docs/ROTO-CONTROL.md, section 3).
public enum RotoHostType: UInt8, Sendable, CaseIterable {
    /// Ableton Live (`01`).
    case ableton = 0x01
    /// Bitwig Studio (`02`).
    case bitwig = 0x02
    /// Logic Pro (`03`). The Roto-Control behaves differently with this type; see the doc.
    case logic = 0x03
}
