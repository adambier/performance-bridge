import Foundation

// What an Arturia instrument sends to a controller it takes for one of Arturia's first KeyLab or
// KeyLab mkII keyboards, and what that controller sends back. docs/ARTURIA.md has the evidence for
// each statement here: tests 1–4 (2026-11-13 and 14, Pigments and Analog Lab V standalone) for
// what is marked "seen", and a reading of the files Arturia installs for the rest;
// docs/ARTURIA-KEYLAB.md sets the profiles side by side. Not affiliated with or endorsed by Arturia.

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

/// The text an instrument sends a KeyLab mkII after a control change from it: the control's name
/// and its value in words. Seen (test 4) from Analog Lab V, with the preset's own label for the
/// control ("Color"), and from Pigments, with the parameter's fixed name ("Macro 1"), three times
/// within 0.1 s of the control change.
public struct ArturiaControlText: Equatable, Sendable {
    /// The control's name (text field 1).
    public var name: String
    /// The value in the instrument's words, e.g., "0.472", "39 %", or "1448 Hz" (text field 2).
    public var valueText: String
    /// The control change number the text is about (field 4).
    public var controller: Int
    /// The control change's value (field 4).
    public var value: Int

    /// Makes a control text.
    public init(name: String, valueText: String, controller: Int, value: Int) {
        self.name = name
        self.valueText = valueText
        self.controller = controller
        self.value = value
    }
}

/// A SysEx message from an Arturia instrument to a controller, in the format the instrument uses
/// for the first KeyLab and KeyLab mkII keyboards (`F0 00 20 6B 7F 42 …`).
public enum ArturiaInstrumentMessage: Equatable, Sendable {
    /// A control's value, 0–127: `7F 42 02 <p> 00 <item> <value>`. `item` is the controller's
    /// number for the control (`ArturiaKeyLabProfile`). Seen (test 1) while Macro 1 was dragged in
    /// the instrument's window, and for eight items when a preset loaded; the inference is that a
    /// preset load reports the items whose values changed.
    case value(item: Int, value: Int)
    /// The display's text: `7F 42 04 <p> 60`, then fields of a tag byte, ASCII text, and a 0 byte.
    /// Seen twice when the instrument first found the controller and twice after the one preset
    /// change tried.
    case text([ArturiaTextField])
    /// The display's text naming a control and its value, sent to a KeyLab mkII after a control
    /// change from it: the same message as `text`, with field 1 the control's name, field 2 the
    /// value in words, field 3 empty, and field 4 "c", the control change's number and value as
    /// two bytes, and ";" (seen, test 4). How a value of 0 is sent has not been seen; it is read
    /// here as the same two bytes, not as the end of the field.
    case controlText(ArturiaControlText)
    /// A light, 0–127: `7F 42 02 <p> 10 <item> <value>`. Seen under the mkII's profile: items 24,
    /// 25, and 34–42 from Pigments and Analog Lab V, and items 31–33 (its three control tabs) from
    /// Analog Lab V alone (tests 4 and 7).
    case light(item: Int, value: Int)
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
        case (0x02, 0x10) where body.count == 7:
            return .light(item: Int(body[5]), value: Int(body[6]))
        case (0x04, 0x60):
            var fields: [ArturiaTextField] = []
            var control: (controller: Int, value: Int)?
            var rest = body[5...]
            while let tag = rest.first {
                rest = rest.dropFirst()
                // Field 4 of a control text holds raw bytes: "c", the number, the value, ";".
                if tag == 4, rest.count >= 4, rest[rest.startIndex] == 0x63, rest[rest.startIndex + 3] == 0x3B {
                    control = (Int(rest[rest.startIndex + 1]), Int(rest[rest.startIndex + 2]))
                    rest = rest.dropFirst(4)
                    if rest.first == 0 { rest = rest.dropFirst() }
                    continue
                }
                let end = rest.firstIndex(of: 0) ?? rest.endIndex
                let text = String(decoding: rest[rest.startIndex..<end].map { $0 & 0x7F }, as: UTF8.self)
                fields.append(ArturiaTextField(tag: Int(tag), text: text))
                rest = end < rest.endIndex ? rest[(end + 1)...] : rest[end...]
            }
            if let control {
                func field(_ tag: Int) -> String { fields.first { $0.tag == tag }?.text ?? "" }
                return .controlText(ArturiaControlText(name: field(1), valueText: field(2),
                                                       controller: control.controller, value: control.value))
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

/// One control of a profile: the control change number the controller sends, and the item number
/// the instrument reports its value under.
public struct ArturiaKeyLabControl: Equatable, Sendable {
    /// The control change number.
    public var controller: Int
    /// The item number.
    public var item: Int

    /// Makes a control.
    public init(controller: Int, item: Int) {
        self.controller = controller
        self.item = item
    }
}

/// The two message formats Arturia's instruments use with KeyLab keyboards.
public enum ArturiaMessageFormat: Equatable, Sendable {
    /// `ArturiaInstrumentMessage`: the first KeyLab and the KeyLab mkII.
    case version2
    /// `ArturiaMk3Message`: the KeyLab mk3.
    case version3
}

/// A controller profile of Arturia's instruments: the port names an instrument recognizes, and
/// the controls it reports values for and takes plain control changes for. Both profiles here use
/// the same messages (`ArturiaInstrumentMessage`); only the mkII's draws `controlText`.
public struct ArturiaKeyLabProfile: Equatable, Sendable {
    /// A name for the profile, as the instruments' Midi Controller menu shows it.
    public var name: String
    /// The port names the profile lists (read from the profile file).
    public var portNames: [String]
    /// The profile's controls (read from the profile file).
    public var controls: [ArturiaKeyLabControl]
    /// The format of the instrument's messages under this profile.
    public var messageFormat: ArturiaMessageFormat

    /// Makes a profile.
    public init(name: String, portNames: [String], controls: [ArturiaKeyLabControl], messageFormat: ArturiaMessageFormat = .version2) {
        self.name = name
        self.portNames = portNames
        self.controls = controls
        self.messageFormat = messageFormat
    }

    /// The first KeyLab keyboards ("KeyLab"). Pigments has been seen to pick it for a port named
    /// "KeyLab 61" (tests 1 and 2). In the "KeyLab" MIDI configuration of nearly every
    /// instrument, 74, 71, 76, and 77 are macros 1–4, 17 is the master volume, 93, 18, 19, and 16
    /// are four parameters of the instrument's own, 7 is unassigned, and 91 is assigned in two
    /// instruments. 74 and item 1 have been seen to be a pair.
    public static let keyLab = ArturiaKeyLabProfile(
        name: "KeyLab",
        portNames: ["KeyLab 25", "KeyLab 49", "KeyLab 61", "KeyLab 88"],
        controls: [(7, 48), (74, 1), (71, 2), (76, 3), (77, 4), (93, 9), (18, 5), (19, 6), (16, 7), (17, 8), (91, 10)]
            .map { ArturiaKeyLabControl(controller: $0.0, item: $0.1) })

    /// The KeyLab mkII keyboards ("KeyLab mkII"). Analog Lab V picked it by itself for a port named
    /// "KeyLab mkII 61"; Pigments needed it chosen by hand (test 4). The same nine control
    /// changes as `keyLab`'s, numbered 1–9 in order; 74 and item 1 and 93 and item 5 have been
    /// seen to be pairs. The profile also lists the names with " MIDI" or " (1)" after them.
    public static let keyLabMkII = ArturiaKeyLabProfile(
        name: "KeyLab mkII",
        portNames: ["KeyLab mkII 49", "KeyLab mkII 61", "KeyLab mkII 88"],
        controls: [74, 71, 76, 77, 93, 18, 19, 16, 17].enumerated()
            .map { ArturiaKeyLabControl(controller: $0.element, item: $0.offset + 1) })

    /// The KeyLab mk3 keyboards ("KeyLab mk3"): the same nine control changes, numbered 0–8, in
    /// the mk3's message format. Pigments and Analog Lab V picked it by themselves for ports
    /// named "KeyLab 61 mk3 MIDI" and "KeyLab 88 mk3 MIDI" (tests 5, 6, and 8); the profile
    /// matches the names anywhere in a port's name.
    public static let keyLabMk3 = ArturiaKeyLabProfile(
        name: "KeyLab mk3",
        portNames: ["KeyLab 49 mk3 MIDI", "KeyLab 61 mk3 MIDI", "KeyLab 88 mk3 MIDI"],
        controls: [74, 71, 76, 77, 93, 18, 19, 16, 17].enumerated()
            .map { ArturiaKeyLabControl(controller: $0.element, item: $0.offset) },
        messageFormat: .version3)

    /// The profile whose port names include this one (for the mkII, also with " MIDI" or " (1)"
    /// after it), or `nil`.
    public static func forPortName(_ name: String) -> ArturiaKeyLabProfile? {
        if keyLabMk3.portNames.contains(name) { return keyLabMk3 }
        if keyLabMkII.portNames.contains(where: { [$0, $0 + " MIDI", $0 + " (1)"].contains(name) }) { return keyLabMkII }
        return keyLab.portNames.contains(name) ? keyLab : nil
    }

    /// The item number an instrument reports for the control with this control change number.
    public func item(forController controller: Int) -> Int? {
        controls.first { $0.controller == controller }?.item
    }

    /// The control change number for the control an instrument reports under this item number.
    public func controller(forItem item: Int) -> Int? {
        controls.first { $0.item == item }?.controller
    }

    /// The control change that sets the control an instrument reports as `item` to `value`
    /// (0–127), on `channel` (1–16; an instrument has been seen to take channel 1). `nil` if the
    /// profile has no such item or a number is out of range. An instrument has been seen not to
    /// report a value back for a change made this way; under the mkII's profile it sends a
    /// `controlText` instead.
    public func controlChange(item: Int, value: Int, channel: Int = 1) -> [UInt8]? {
        guard let controller = controller(forItem: item), (0...127).contains(value), (1...16).contains(channel) else {
            return nil
        }
        return [UInt8(0xB0 + channel - 1), UInt8(controller), UInt8(value)]
    }
}
