import Foundation

// What an Arturia instrument sends to a controller it takes for one of Arturia's first KeyLab
// keyboards, and what that controller sends back. docs/ARTURIA.md has the evidence for each
// statement here: test 1 (2026-11-13, Pigments 7.0.1 standalone) for what is marked "seen", and a
// reading of the files Arturia installs for the rest. Not affiliated with or endorsed by Arturia.

/// One text field of the display message: a tag (1–4 have been seen) and its text.
public struct ArturiaTextField: Equatable, Sendable {
    /// The byte before the text. Seen: 1 the instrument's name, 2 the preset's name, 3 a second
    /// line about the preset (its type, by the two presets seen), 4 empty.
    public var tag: Int
    /// The text, ASCII.
    public var text: String

    /// Makes a text field.
    public init(tag: Int, text: String) {
        self.tag = tag
        self.text = text
    }
}

/// A SysEx message from an Arturia instrument to a controller, in the format the instrument uses
/// for the first KeyLab keyboards (`F0 00 20 6B 7F 42 …`).
public enum ArturiaInstrumentMessage: Equatable, Sendable {
    /// A control's value, 0–127: `7F 42 02 <p> 00 <item> <value>`. `item` is the controller's
    /// number for the control (`ArturiaKeyLabProfile`). Seen whenever the parameter changed in the
    /// instrument's own window, and for each changed parameter when a preset loaded.
    case value(item: Int, value: Int)
    /// The display's text: `7F 42 04 <p> 60`, then fields of a tag byte, ASCII text, and a 0 byte.
    /// Seen when the instrument first found the controller and after each preset change, twice
    /// each time.
    case text([ArturiaTextField])
    /// Any other Arturia SysEx message, whole, from `F0` to `F7`.
    case other([UInt8])

    /// Arturia's manufacturer ID.
    public static let manufacturerID: [UInt8] = [0x00, 0x20, 0x6B]

    /// Reads one complete SysEx message (`F0` … `F7`). `nil` if it is not Arturia's.
    public static func parse(_ message: [UInt8]) -> ArturiaInstrumentMessage? {
        guard message.count >= 5, message.first == 0xF0, message.last == 0xF7,
              Array(message[1...3]) == manufacturerID else { return nil }
        let body = Array(message[4..<(message.count - 1)])
        // body: 7F 42 <kind> <p> <sub> …
        guard body.count >= 5, body[0] == 0x7F, body[1] == 0x42 else { return .other(message) }
        switch (body[2], body[4]) {
        case (0x02, 0x00) where body.count == 7:
            return .value(item: Int(body[5]), value: Int(body[6]))
        case (0x04, 0x60):
            var fields: [ArturiaTextField] = []
            var rest = body[5...]
            while let tag = rest.first {
                rest = rest.dropFirst()
                let end = rest.firstIndex(of: 0) ?? rest.endIndex
                let text = String(decoding: rest[rest.startIndex..<end].map { $0 & 0x7F }, as: UTF8.self)
                fields.append(ArturiaTextField(tag: Int(tag), text: text))
                rest = end < rest.endIndex ? rest[(end + 1)...] : rest[end...]
            }
            return .text(fields)
        default:
            return .other(message)
        }
    }
}

/// Joins the pieces a MIDI connection delivers into complete SysEx messages. Bytes outside a
/// SysEx message (notes, control changes) are dropped: an instrument has been seen to send a
/// controller nothing else.
public struct ArturiaSysExAssembler: Sendable {
    private var pending: [UInt8]?

    /// Makes an assembler with nothing pending.
    public init() {}

    /// Takes the next bytes received and returns every SysEx message they complete, each from
    /// `F0` to `F7`. A message cut off by a new `F0` or another status byte is dropped.
    public mutating func feed<S: Sequence>(_ bytes: S) -> [[UInt8]] where S.Element == UInt8 {
        var complete: [[UInt8]] = []
        for byte in bytes {
            if byte == 0xF0 {
                pending = [byte]
            } else if byte == 0xF7 {
                if var message = pending {
                    message.append(byte)
                    complete.append(message)
                }
                pending = nil
            } else if byte >= 0xF8 {
                continue  // Real-time bytes may come in the middle of a message.
            } else if byte >= 0x80 {
                pending = nil
            } else {
                pending?.append(byte)
            }
        }
        return complete
    }
}

/// The controller profile Arturia's instruments name "KeyLab": the first KeyLab keyboards. An
/// instrument picks it for a MIDI port with one of `portNames` (Pigments has been seen to, for
/// "KeyLab 61"), then reports values for the controls below and takes plain control changes for
/// them.
public enum ArturiaKeyLabProfile {
    /// The port names the profile lists, which an instrument matches exactly (read from the
    /// profile file; only "KeyLab 61" has been tried).
    public static let portNames = ["KeyLab 25", "KeyLab 49", "KeyLab 61", "KeyLab 88"]

    /// The profile's controls: the control change number the controller sends, and the item
    /// number the instrument reports the value under (read from the profile file; 74 and item 1
    /// have been seen to be a pair). In the "KeyLab" MIDI configuration of nearly every
    /// instrument, 74, 71, 76, and 77 are macros 1–4, 17 is the master volume, 93, 18, 19, and 16
    /// are four parameters of the instrument's own, and 7 and 91 are mostly unassigned.
    public static let controls: [(controller: Int, item: Int)] = [
        (7, 48), (74, 1), (71, 2), (76, 3), (77, 4), (93, 9), (18, 5), (19, 6), (16, 7), (17, 8), (91, 10),
    ]

    /// The item number an instrument reports for the control with this control change number.
    public static func item(forController controller: Int) -> Int? {
        controls.first { $0.controller == controller }?.item
    }

    /// The control change number for the control an instrument reports under this item number.
    public static func controller(forItem item: Int) -> Int? {
        controls.first { $0.item == item }?.controller
    }

    /// The control change that sets the control an instrument reports as `item` to `value`
    /// (0–127), on `channel` (1–16; an instrument has been seen to take channel 1). `nil` if the
    /// profile has no such item or a number is out of range. An instrument has been seen not to
    /// report a value back for a change made this way.
    public static func controlChange(item: Int, value: Int, channel: Int = 1) -> [UInt8]? {
        guard let controller = controller(forItem: item), (0...127).contains(value), (1...16).contains(channel) else {
            return nil
        }
        return [UInt8(0xB0 + channel - 1), UInt8(controller), UInt8(value)]
    }
}
