import Foundation

// What an Arturia instrument sends a controller it takes for a KeyLab mk3, read from the bytes of
// two runs (docs/ARTURIA.md, tests 5 and 6, with Pigments and Analog Lab V standalone) and the
// installed profile files; docs/ARTURIA-KEYLAB.md, section 5, sets it out. Not every field is
// worked out. Not affiliated with or endorsed by Arturia.

/// A SysEx message in the format an Arturia instrument uses for the KeyLab mk3:
/// `F0 00 20 6B 7F 42 00 <id> …`, where `<id>` has been seen to be 13 from Pigments and 1 from
/// Analog Lab V, the numbers their profile files give.
public enum ArturiaMk3Message: Equatable, Sendable {
    /// The id Analog Lab V's messages carry.
    public static let analogLabID = 1
    /// The id the instruments' messages carry (Pigments; the shared profile file).
    public static let instrumentID = 13

    /// Connect (`05 01`) or disconnect (`05 00`).
    case connect(Bool, id: Int)
    /// A property of an item: `00 <item> <index> <value> 00`. Index 1 is a knob's value (0–127),
    /// items 0–8; index 2, items 51–54, has been seen from Analog Lab V alone.
    case property(item: Int, index: Int, value: Int, id: Int)
    /// The preset's screen (`04 10`): the preset's name, whether an asterisk after it marked it
    /// as changed, and its subtype or type. `picture` is a number that differed by instrument in
    /// three presets (45 Pigments, 22 Augmented VOICES, 59 Memory V); that it chooses the picture
    /// the keyboard shows is an inference.
    case preset(name: String, isChanged: Bool, kind: String, picture: Int?, id: Int)
    /// The screen sent after a control change from the controller (`04 1C`): the control's value
    /// in words, its name, and the control change's value. It does not say which control; it has
    /// been seen about 30 ms after the control change, three times.
    case controlScreen(valueText: String, name: String, value: Int?, id: Int)
    /// Any other message in the format.
    case other([UInt8])

    /// Parses one complete SysEx message (`F0` … `F7`). `nil` if it is not in this format.
    public static func parse(_ message: [UInt8]) -> ArturiaMk3Message? {
        let header: [UInt8] = [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x00]
        guard message.count >= header.count + 4, Array(message[0..<header.count]) == header, message.last == 0xF7 else {
            return nil
        }
        let id = Int(message[header.count])
        let body = Array(message[(header.count + 1)..<(message.count - 1)])
        switch body[0] {
        case 0x05 where body.count == 2:
            return .connect(body[1] != 0, id: id)
        case 0x00 where body.count == 5:
            return .property(item: Int(body[1]), index: Int(body[2]), value: Int(body[3]), id: id)
        case 0x04 where body.count >= 3 && body[1] == 0x10:
            // Field 0, the name; field 1, one byte; field 3, the type; then fields 4, 5, and 6.
            var rest = body[2...]
            guard let name = text(tag: 0, from: &rest) else { return .other(message) }
            if rest.count >= 3, rest.first == 1 { rest = rest.dropFirst(3) }
            let kind = text(tag: 3, from: &rest) ?? ""
            let tail = Array(rest)
            let picture = tail.count >= 10 && tail[0] == 4 && tail[3] == 5 && tail[8] == 6 ? Int(tail[9]) : nil
            let isChanged = name.hasSuffix("*")
            return .preset(name: isChanged ? String(name.dropLast()) : name, isChanged: isChanged, kind: kind, picture: picture, id: id)
        case 0x04 where body.count >= 3 && body[1] == 0x1C:
            var rest = body[2...]
            guard let valueText = text(tag: 0, from: &rest), let name = text(tag: 1, from: &rest) else { return .other(message) }
            let value = rest.count >= 2 && rest.first == 2 ? Int(rest[rest.startIndex + 1]) : nil
            return .controlScreen(valueText: valueText, name: name, value: value, id: id)
        default:
            return .other(message)
        }
    }

    /// Takes a text field with this tag off the front of `rest`: the tag, the text, and a 0 byte.
    private static func text(tag: UInt8, from rest: inout ArraySlice<UInt8>) -> String? {
        guard rest.first == tag else { return nil }
        let content = rest.dropFirst()
        guard let end = content.firstIndex(of: 0) else { return nil }
        rest = content[(end + 1)...]
        return String(decoding: content[..<end], as: UTF8.self)
    }

    /// The message that gives a knob its value, as an instrument sends it:
    /// `F0 00 20 6B 7F 42 00 <id> 00 <item> 01 <value> 00 F7`.
    public static func knobValue(item: Int, value: Int, id: Int) -> [UInt8] {
        [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x00, UInt8(id & 0x7F), 0x00, UInt8(item & 0x7F), 0x01, UInt8(min(max(value, 0), 127)), 0x00, 0xF7]
    }
}
