import Foundation

/// A MIDI message as `RotoMIDIParser` splits it out of a byte stream.
public enum RotoMIDIMessage: Equatable, Sendable {
    /// A complete SysEx message, `F0` through `F7`.
    case sysEx([UInt8])
    /// A control change: channel 0–15, controller, and value.
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    /// Any other channel message, status byte first.
    case other([UInt8])
}

/// Splits a stream of MIDI bytes into messages.
///
/// The bytes may arrive in chunks of any size, so a SysEx message can span several chunks. The
/// parser follows running status, skips real-time bytes (`F8`–`FF`) wherever they appear, and drops
/// a SysEx message that another status byte interrupts or that grows past `maximumSysExLength`.
/// System common messages other than SysEx are skipped.
public struct RotoMIDIParser: Sendable {
    /// The longest SysEx message kept. The longest the Roto-Control's MIX mode defines, SEND TRACK
    /// NAMES, is 113 bytes.
    public static let maximumSysExLength = 512

    private var sysEx: [UInt8]? = nil
    private var runningStatus: UInt8? = nil
    private var data: [UInt8] = []
    private var skippingSystemCommon = false

    /// Makes a parser with no partial message.
    public init() {}

    /// Feeds bytes and returns the messages they complete.
    public mutating func feed<S: Sequence>(_ bytes: S) -> [RotoMIDIMessage] where S.Element == UInt8 {
        var messages: [RotoMIDIMessage] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte == 0xF0 {
                sysEx = [0xF0]
                runningStatus = nil
                data = []
                skippingSystemCommon = false
                continue
            }
            if byte == 0xF7 {
                if var message = sysEx {
                    message.append(0xF7)
                    messages.append(.sysEx(message))
                }
                sysEx = nil
                continue
            }
            if byte & 0x80 != 0 {
                sysEx = nil
                data = []
                if byte >= 0xF1 {
                    runningStatus = nil
                    skippingSystemCommon = true
                } else {
                    runningStatus = byte
                    skippingSystemCommon = false
                }
                continue
            }
            if sysEx != nil {
                if sysEx!.count >= Self.maximumSysExLength { sysEx = nil } else { sysEx!.append(byte) }
                continue
            }
            guard !skippingSystemCommon, let status = runningStatus else { continue }
            data.append(byte)
            if data.count == Self.dataLength(status) {
                messages.append(Self.message(status, data))
                data = []
            }
        }
        return messages
    }

    private static func dataLength(_ status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0: return 1
        default: return 2
        }
    }

    private static func message(_ status: UInt8, _ data: [UInt8]) -> RotoMIDIMessage {
        if status & 0xF0 == 0xB0 {
            return .controlChange(channel: status & 0x0F, controller: data[0], value: data[1])
        }
        return .other([status] + data)
    }
}
