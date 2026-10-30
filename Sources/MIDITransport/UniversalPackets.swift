import Foundation

/// Conversion between MIDI 1.0 byte streams and the Universal MIDI Packet (UMP) words that
/// CoreMIDI's event lists carry.
///
/// CoreMIDI's current API delivers and accepts MIDI as UMP words. With the MIDI 1.0 protocol, a
/// channel message is one 32-bit word of type 2, a real-time or system common message one word of
/// type 1, and a SysEx message a series of 64-bit packets of type 3, each carrying up to six data
/// bytes. This conversion follows the UMP format in the MIDI Association's "Universal MIDI Packet
/// (UMP) Format and MIDI 2.0 Protocol" specification. All messages use group 0.
public enum UniversalPackets {
    /// MIDI 1.0 bytes for UMP words. SysEx packets become `F0`, their data bytes, and `F7`, so a
    /// SysEx message split across several calls comes out split the same way. Packet types that
    /// carry no MIDI 1.0 message (for example utility messages and MIDI 2.0 channel voice) are
    /// skipped.
    public static func bytes(fromWords words: [UInt32]) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let type = Int(word >> 28)
            let length = wordCount(forType: type)
            defer { index += length }
            switch type {
            case 0x1, 0x2:
                let status = UInt8((word >> 16) & 0xFF)
                let valid = type == 0x2 ? (0x80...0xEF).contains(status) : status >= 0xF1 && status != 0xF7
                guard valid else { continue }
                let data = [UInt8((word >> 8) & 0x7F), UInt8(word & 0x7F)]
                bytes.append(status)
                bytes.append(contentsOf: data.prefix(dataLength(forStatus: status)))
            case 0x3:
                guard index + 1 < words.count else { continue }
                let second = words[index + 1]
                let form = Int((word >> 20) & 0xF)
                guard form <= 3 else { continue }
                let count = min(Int((word >> 16) & 0xF), 6)
                let payload: [UInt8] = [UInt8((word >> 8) & 0x7F), UInt8(word & 0x7F),
                                        UInt8((second >> 24) & 0x7F), UInt8((second >> 16) & 0x7F),
                                        UInt8((second >> 8) & 0x7F), UInt8(second & 0x7F)]
                if form == 0 || form == 1 { bytes.append(0xF0) }
                bytes.append(contentsOf: payload.prefix(count))
                if form == 0 || form == 3 { bytes.append(0xF7) }
            default:
                continue
            }
        }
        return bytes
    }

    /// UMP words for MIDI 1.0 bytes. The bytes must be complete messages with their status bytes
    /// (no running status), as `RotoOutgoing` and `RotoFeedback` produce them. A SysEx message
    /// must be whole, from `F0` to `F7`. Bytes that do not start a message are skipped.
    public static func words(fromBytes bytes: [UInt8]) -> [UInt32] {
        var words: [UInt32] = []
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            if status == 0xF0 {
                guard let end = bytes[(index + 1)...].firstIndex(of: 0xF7) else { break }
                words.append(contentsOf: sysExWords(Array(bytes[(index + 1)..<end])))
                index = end + 1
            } else if status >= 0x80 && status != 0xF7 {
                let length = dataLength(forStatus: status)
                guard index + length < bytes.count else { break }
                let data = (0..<2).map { $0 < length ? UInt32(bytes[index + 1 + $0] & 0x7F) : 0 }
                let type: UInt32 = status >= 0xF0 ? 0x1 : 0x2
                words.append(type << 28 | UInt32(status) << 16 | data[0] << 8 | data[1])
                index += 1 + length
            } else {
                index += 1
            }
        }
        return words
    }

    /// Words split into whole packets, by each packet's message type. A packet cut short at the end
    /// is returned as it is.
    public static func packets(_ words: [UInt32]) -> [ArraySlice<UInt32>] {
        var result: [ArraySlice<UInt32>] = []
        var index = 0
        while index < words.count {
            let end = min(index + wordCount(forType: Int(words[index] >> 28)), words.count)
            result.append(words[index..<end])
            index = end
        }
        return result
    }

    /// The number of 32-bit words in a packet of a given message type.
    public static func wordCount(forType type: Int) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4
        }
    }

    /// The SysEx data bytes (without `F0` and `F7`) as type-3 packets of up to six bytes.
    static func sysExWords(_ data: [UInt8]) -> [UInt32] {
        let chunks = data.isEmpty ? [[]] : stride(from: 0, to: data.count, by: 6).map {
            Array(data[$0..<min($0 + 6, data.count)])
        }
        var words: [UInt32] = []
        for (number, chunk) in chunks.enumerated() {
            let form: UInt32
            switch (number == 0, number == chunks.count - 1) {
            case (true, true): form = 0
            case (true, false): form = 1
            case (false, false): form = 2
            case (false, true): form = 3
            }
            let padded = chunk.map { UInt32($0 & 0x7F) } + Array(repeating: 0, count: 6 - chunk.count)
            words.append(0x3 << 28 | form << 20 | UInt32(chunk.count) << 16 | padded[0] << 8 | padded[1])
            words.append(padded[2] << 24 | padded[3] << 16 | padded[4] << 8 | padded[5])
        }
        return words
    }

    /// The number of data bytes after a status byte in MIDI 1.0.
    static func dataLength(forStatus status: UInt8) -> Int {
        switch status {
        case 0x80...0xBF, 0xE0...0xEF: return 2
        case 0xC0...0xDF: return 1
        case 0xF1, 0xF3: return 1
        case 0xF2: return 2
        default: return 0
        }
    }
}
