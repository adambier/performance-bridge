// What the Launch Control XL 3 sends on its DAW port in DAW mode, read from raw MIDI bytes.
// Source: Novation's "Launch Control XL 3 programmer's reference guide", version 1.0 (April 2026).
// Not yet checked on the device (docs/LAUNCH-CONTROL-XL3.md).

import Foundation

/// Something the Launch Control XL 3 reported.
public enum LaunchControlEvent: Equatable, Sendable {
    /// A fader, or an encoder in absolute mode, moved to `value` (0–127).
    case moved(LaunchControlElement, value: UInt8)
    /// An encoder in relative mode turned by `steps`: positive clockwise, negative anticlockwise
    /// (the value less 64).
    case turned(LaunchControlElement, steps: Int)
    /// A button was pressed (`true`) or released (`false`). That a button sends 127 when pressed
    /// and 0 when released is an inference; the guide gives no values.
    case button(LaunchControlElement, pressed: Bool)
    /// A fader or an encoder was touched (`true`) or let go (`false`), with touch reports on
    /// (channel 15).
    case touch(LaunchControlElement, touched: Bool)
    /// The surface mode changed, by the user or on request (channel 7, Control Change 30).
    case mode(LaunchControlMode)
    /// Any other feature control's reply (channel 7).
    case feature(number: UInt8, value: UInt8)
    /// The device is ready for the next bitmap (SysEx 09h 7Fh).
    case bitmapReady
    /// A message this library doesn't read, with its bytes.
    case unknown([UInt8])

    /// What a channel message (status, and one or two data bytes) reports.
    public init(status: UInt8, _ data1: UInt8, _ data2: UInt8) {
        let channel = status & 0x0F
        guard status & 0xF0 == 0xB0 else {
            self = .unknown([status, data1, data2])
            return
        }
        switch channel {
        case 15:
            if let element = LaunchControlElement(channel: 15, controlNumber: data1) {
                self = .moved(element, value: data2)
            } else if (77...100).contains(data1) {
                let index = Int(data1) - 77
                self = .turned(.encoder(row: index / 8, column: index % 8), steps: Int(data2) - 64)
            } else {
                self = .unknown([status, data1, data2])
            }
        case 14:
            // Touch reports use the controls' own numbers (e.g., BEh 05h 7Fh for the first fader).
            if let element = LaunchControlElement(channel: 15, controlNumber: data1) {
                self = .touch(element, touched: data2 >= 64)
            } else {
                self = .unknown([status, data1, data2])
            }
        case 6:
            if data1 == 0x1E, let mode = LaunchControlMode(value: data2) {
                self = .mode(mode)
            } else if data1 == 0x3F {
                self = .button(.shift, pressed: data2 >= 64)
            } else {
                self = .feature(number: data1, value: data2)
            }
        case 0:
            if let element = LaunchControlElement(channel: 0, controlNumber: data1) {
                self = .button(element, pressed: data2 >= 64)
            } else {
                self = .unknown([status, data1, data2])
            }
        default:
            self = .unknown([status, data1, data2])
        }
    }

    /// What a whole SysEx message (F0h to F7h) reports.
    public init(sysEx bytes: [UInt8]) {
        let header = LaunchControlOutgoing.sysExHeader
        if bytes.count >= header.count + 2, Array(bytes.prefix(header.count)) == header,
           bytes[header.count] == 0x09, bytes[header.count + 1] == 0x7F {
            self = .bitmapReady
        } else {
            self = .unknown(bytes)
        }
    }
}

/// Reads the Launch Control XL 3's MIDI bytes as they arrive, which may split or join messages:
/// channel messages (with running status), SysEx, and real-time bytes, which are skipped.
public struct LaunchControlParser: Sendable {
    /// The longest SysEx message kept; a longer one is dropped.
    public static let maximumSysExLength = 2048

    private var status: UInt8?
    private var data: [UInt8] = []
    private var sysEx: [UInt8]?

    /// A parser with nothing pending.
    public init() {}

    /// Reads `bytes` and returns the events they complete.
    public mutating func feed<S: Sequence>(_ bytes: S) -> [LaunchControlEvent] where S.Element == UInt8 {
        var events: [LaunchControlEvent] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }  // Real-time: clock, active sensing, and so on.
            if byte == 0xF0 {
                sysEx = [byte]
                status = nil
                continue
            }
            if byte == 0xF7 {
                if var message = sysEx {
                    message.append(byte)
                    events.append(LaunchControlEvent(sysEx: message))
                }
                sysEx = nil
                continue
            }
            if var message = sysEx {
                if byte >= 0x80 {
                    // A status byte ends an unfinished SysEx message, which is dropped.
                    sysEx = nil
                } else {
                    message.append(byte)
                    sysEx = message.count <= Self.maximumSysExLength ? message : nil
                    continue
                }
            }
            if byte >= 0x80 {
                status = byte < 0xF0 ? byte : nil
                data = []
                continue
            }
            guard let current = status else { continue }
            data.append(byte)
            let needed = (current & 0xF0 == 0xC0 || current & 0xF0 == 0xD0) ? 1 : 2
            if data.count == needed {
                events.append(LaunchControlEvent(status: current, data[0], needed == 2 ? data[1] : 0))
                data = []  // Running status: the next data bytes reuse `current`.
            }
        }
        return events
    }
}
