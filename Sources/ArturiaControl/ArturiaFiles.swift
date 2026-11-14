import Foundation

// Readers for three kinds of file Arturia's instruments install or keep, so that a controller can
// show a control's name before the control is moved. Read-only, and pure: each takes a file's
// contents. docs/ARTURIA.md, section 4, has what was read and how far it has been checked
// (Pigments only, 2026-11-14); the formats are not published. Not affiliated with or endorsed by
// Arturia.

/// A search for a byte pattern, for the readers below.
enum ArturiaBytes {
    /// The index of the first occurrence of `pattern` in `bytes` at or after `start`, or `nil`.
    static func firstIndex(of pattern: [UInt8], in bytes: [UInt8], from start: Int = 0) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count, start >= 0 else { return nil }
        let first = pattern[0]
        var index = start
        let last = bytes.count - pattern.count
        while index <= last {
            if bytes[index] == first {
                var matched = true
                var offset = 1
                while offset < pattern.count {
                    if bytes[index + offset] != pattern[offset] { matched = false; break }
                    offset += 1
                }
                if matched { return index }
            }
            index += 1
        }
        return nil
    }

    /// The ASCII token (up to the next space or the end) starting at `index`, and the index after
    /// the space that ends it.
    static func token(in bytes: [UInt8], at index: Int) -> (text: String, next: Int)? {
        guard index < bytes.count else { return nil }
        var end = index
        while end < bytes.count, bytes[end] != 0x20, bytes[end] != 0x0A { end += 1 }
        guard end > index else { return nil }
        return (String(decoding: bytes[index..<end], as: UTF8.self), min(end + 1, bytes.count))
    }
}

/// What a controller needs from one of an instrument's preset files: the preset's name, its type,
/// and the labels and values it gives the four macros.
///
/// The files are a text serialization in which a string is its length, a space, and its bytes,
/// and a parameter is its name as such a string followed by its value (read in Pigments' and nine
/// other instruments' factory presets; not published by Arturia). A macro's label is the string
/// named `Macro1_Name` (to 4), which some instruments pad with 0 bytes.
public struct ArturiaPresetFile: Equatable, Sendable {
    /// The preset's name.
    public var name: String
    /// The preset's subtype (e.g., "Evolving Keys"), or its type where it has no subtype, or "".
    /// An instrument has been seen to send this as the third field of its text.
    public var kind: String
    /// The four macros' labels; `nil` where the file has none.
    public var macroLabels: [String?]
    /// The four macros' values, 0–1, where the file has parameters named `Macro1` to `Macro4`
    /// (Pigments' files do).
    public var macroValues: [Double?]
    /// The parameter `MasterVolume`, 0–1, if the file has it.
    public var masterVolume: Double?

    /// Makes a preset description.
    public init(name: String, kind: String, macroLabels: [String?], macroValues: [Double?] = [nil, nil, nil, nil],
                masterVolume: Double? = nil) {
        self.name = name
        self.kind = kind
        self.macroLabels = macroLabels
        self.macroValues = macroValues
        self.masterVolume = masterVolume
    }

    /// Reads a preset file's bytes. `nil` if they don't begin as these files do.
    public init?(bytes: [UInt8]) {
        let header = Array("22 serialization::archive ".utf8)
        guard bytes.count > header.count, Array(bytes[0..<header.count]) == header else { return nil }
        // Five numbers, then the name as a string.
        var index = header.count
        for _ in 0..<5 {
            guard let token = ArturiaBytes.token(in: bytes, at: index) else { return nil }
            index = token.next
        }
        guard let name = Self.string(in: bytes, at: index) else { return nil }
        self.name = name
        kind = Self.string(named: "Subtype", in: bytes) ?? Self.string(named: "Type", in: bytes) ?? ""
        macroLabels = (1...4).map { Self.string(named: "Macro\($0)_Name", in: bytes) }
        macroValues = (1...4).map { Self.number(named: "Macro\($0)", in: bytes) }
        masterVolume = Self.number(named: "MasterVolume", in: bytes)
    }

    /// The string at `index`: a length, a space, and that many bytes, cut at the first 0 byte.
    private static func string(in bytes: [UInt8], at index: Int) -> String? {
        guard let length = ArturiaBytes.token(in: bytes, at: index), let count = Int(length.text), count >= 0,
              length.next + count <= bytes.count else { return nil }
        let raw = bytes[length.next..<(length.next + count)]
        return String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Where the value of the first parameter or property named `key` starts.
    private static func value(named key: String, in bytes: [UInt8]) -> Int? {
        let pattern = Array(" \(key.utf8.count) \(key) ".utf8)
        return ArturiaBytes.firstIndex(of: pattern, in: bytes).map { $0 + pattern.count }
    }

    private static func string(named key: String, in bytes: [UInt8]) -> String? {
        value(named: key, in: bytes).flatMap { string(in: bytes, at: $0) }
    }

    private static func number(named key: String, in bytes: [UInt8]) -> Double? {
        value(named: key, in: bytes).flatMap { ArturiaBytes.token(in: bytes, at: $0) }.flatMap { Double($0.text) }
    }
}

/// Choosing, among preset files, the one an instrument has loaded, from what the instrument sends
/// a controller: the preset's name (cut to 15 characters; seen), its type, and its values.
///
/// Of Pigments' 9,392 factory presets (read 2026-11-14), the name as sent is shared by presets
/// with different macro labels for 387; the name and type for 85; and the name, type, and values
/// for 2. Where the choice stays open between different labels, there is no answer.
public enum ArturiaPresetMatch {
    /// The longest preset name an instrument sends in its text (seen: 15 characters after the
    /// asterisk, of names up to 27 long).
    public static let sentNameLength = 15

    /// Whether a preset named `name` would be sent as `sent`.
    public static func name(_ name: String, matchesSent sent: String) -> Bool {
        name == sent || (sent.count >= sentNameLength && name.hasPrefix(sent))
    }

    /// The four macro labels of the preset among `candidates` that the instrument has loaded, or
    /// `nil` if none matches `name` or the matches that remain differ in their labels.
    ///
    /// - Parameters:
    ///   - name: the preset's name as sent, without its asterisk.
    ///   - kind: the text's third field (the preset's subtype or type), or "".
    ///   - macroValues: the four macros' values as the instrument reported them (0–127), `nil`
    ///     where unknown.
    ///   - volume: the master volume as reported (0–127), or `nil`.
    public static func macroLabels(among candidates: [ArturiaPresetFile], name: String, kind: String,
                                   macroValues: [Int?] = [nil, nil, nil, nil], volume: Int? = nil) -> [String?]? {
        var matches = candidates.filter { Self.name($0.name, matchesSent: name) }
        guard !matches.isEmpty else { return nil }
        if let labels = agreed(matches) { return labels }
        if !kind.isEmpty {
            let ofKind = matches.filter { $0.kind == kind }
            if !ofKind.isEmpty { matches = ofKind }
            if let labels = agreed(matches) { return labels }
        }
        guard macroValues.contains(where: { $0 != nil }) || volume != nil else { return nil }
        // A reported value has been seen to differ by 1 from the file's value × 127, rounded.
        func near(_ stored: Double?, _ reported: Int?, _ tolerance: Double) -> Bool {
            guard let reported else { return true }
            guard let stored else { return false }
            return abs(stored * 127 - Double(reported)) <= tolerance
        }
        matches = matches.filter { preset in
            zip(preset.macroValues, macroValues).allSatisfy { near($0, $1, 1.5) } && near(preset.masterVolume, volume, 2.5)
        }
        return agreed(matches)
    }

    /// The labels all of `presets` share, or `nil` if there are none or they differ.
    private static func agreed(_ presets: [ArturiaPresetFile]) -> [String?]? {
        guard let first = presets.first, presets.allSatisfy({ $0.macroLabels == first.macroLabels }) else { return nil }
        return first.macroLabels
    }
}

/// An instrument's factory MIDI assignments and parameter names, for naming the controls of a
/// controller profile before they are moved.
public enum ArturiaParameterFiles {
    /// The control changes a MIDI configuration assigns, by control change number, each with its
    /// parameter number: read from the contents of an instrument's `plugin.prefmidi.xml`, for
    /// the configuration named `configuration` ("KeyLab" is the one the KeyLab profiles use).
    /// Assignments the user makes by MIDI learn are not in this file.
    public static func assignments(inMIDIConfigurations xml: String, configuration: String = "KeyLab") -> [Int: Int] {
        guard let start = xml.range(of: "<midiconfig name=\"\(configuration)\">") else { return [:] }
        let rest = xml[start.upperBound...]
        let body = rest.range(of: "</midiconfig>").map { rest[..<$0.lowerBound] } ?? rest
        var result: [Int: Int] = [:]
        for element in body.components(separatedBy: "<assignment ").dropFirst() {
            let tag = element.prefix { $0 != ">" }
            guard let controller = attribute("controller", in: tag).flatMap({ Int($0) }),
                  let parameter = attribute("paramid", in: tag).flatMap({ Int($0) }) else { continue }
            result[controller] = parameter
        }
        return result
    }

    /// The display names of an instrument's parameters, in order: read from the first `vst`
    /// section of the contents of its `Reference_ParamNames.xml`. That a parameter's number in
    /// the MIDI configurations is its position here, from 0, is an inference: it gives the names
    /// Pigments sent for five control changes (docs/ARTURIA.md, test 7), and has not been checked
    /// for another instrument.
    public static func displayNames(inParameterNames xml: String) -> [String] {
        guard let start = xml.range(of: "<vst>") else { return [] }
        let rest = xml[start.upperBound...]
        let body = rest.range(of: "</vst>").map { rest[..<$0.lowerBound] } ?? rest
        return body.components(separatedBy: "<param ").dropFirst().map { element in
            attribute("display_name", in: element.prefix { $0 != ">" }) ?? ""
        }
    }

    /// Each assigned control change's parameter name, from the two files' contents.
    public static func names(midiConfigurations: String, parameterNames: String, configuration: String = "KeyLab") -> [Int: String] {
        let names = displayNames(inParameterNames: parameterNames)
        var result: [Int: String] = [:]
        for (controller, parameter) in assignments(inMIDIConfigurations: midiConfigurations, configuration: configuration)
        where parameter >= 0 && parameter < names.count && !names[parameter].isEmpty {
            result[controller] = names[parameter]
        }
        return result
    }

    /// The value of `name="…"` in an XML tag's text.
    private static func attribute(_ name: String, in tag: Substring) -> String? {
        guard let start = tag.range(of: " \(name)=\"") ?? tag.range(of: "\(name)=\"") else { return nil }
        let rest = tag[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}
