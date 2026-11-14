import XCTest
@testable import ArturiaControl

/// The file contents below are made up in the layout read from Arturia's files (docs/ARTURIA.md,
/// section 4); none is copied from them.
final class ArturiaFilesTests: XCTestCase {
    /// A string as the preset files write one: its length, a space, and its bytes.
    private func string(_ text: String, paddedTo length: Int? = nil) -> [UInt8] {
        var bytes = Array(text.utf8)
        if let length { bytes += [UInt8](repeating: 0, count: max(length - bytes.count, 0)) }
        return Array("\(bytes.count) ".utf8) + bytes
    }

    /// A made-up preset file.
    private func preset(name: String, subtype: String? = nil, type: String? = "Keys", labels: [String],
                        values: [Double] = [0, 0, 0, 0], volume: Double? = nil, padded: Bool = true) -> [UInt8] {
        var bytes = Array("22 serialization::archive 10 0 7 0 7 ".utf8) + string(name) + Array(" 4 Bank 0 ".utf8)
        bytes += Array("18 OriginalPresetName ".utf8) + string(name)
        if let subtype { bytes += Array(" 7 Subtype ".utf8) + string(subtype) }
        if let type { bytes += Array(" 4 Type ".utf8) + string(type) }
        bytes += Array(" 15 Aftertouch Type 0 6 Legato 1".utf8)
        for (index, value) in values.enumerated() { bytes += Array(" 6 Macro\(index + 1) \(value)".utf8) }
        if let volume { bytes += Array(" 12 MasterVolume \(volume)".utf8) }
        for (index, label) in labels.enumerated() {
            bytes += Array(" 11 Macro\(index + 1)_Name ".utf8) + string(label, paddedTo: padded ? 16 : nil)
        }
        return bytes + Array(" 11 MicroTuning 0\n".utf8)
    }

    func testPresetFile() {
        let file = ArturiaPresetFile(bytes: preset(name: "Glass Threads", subtype: "Evolving Keys",
                                                   labels: ["Timbre", "Time", "Inharmonicity", "Delay"],
                                                   values: [0, 0.8, 0, 0.272], volume: 0.544))
        XCTAssertEqual(file, ArturiaPresetFile(name: "Glass Threads", kind: "Evolving Keys",
                                               macroLabels: ["Timbre", "Time", "Inharmonicity", "Delay"],
                                               macroValues: [0, 0.8, 0, 0.272], masterVolume: 0.544))
        // No subtype: the type. Labels without padding, as some instruments write them.
        let plain = ArturiaPresetFile(bytes: preset(name: "Start", type: "Template", labels: ["Brightness", "", "Time", "Movement"], padded: false))
        XCTAssertEqual(plain?.kind, "Template")
        XCTAssertEqual(plain?.macroLabels, ["Brightness", "", "Time", "Movement"])
        XCTAssertNil(plain?.masterVolume)
        // Neither, and fewer labels.
        let bare = ArturiaPresetFile(bytes: preset(name: "Bare", type: nil, labels: ["One"]))
        XCTAssertEqual(bare?.kind, "")
        XCTAssertEqual(bare?.macroLabels, ["One", nil, nil, nil])
        // Not a preset file, and one cut short.
        XCTAssertNil(ArturiaPresetFile(bytes: Array("<?xml version=\"1.0\"?>".utf8)))
        XCTAssertNil(ArturiaPresetFile(bytes: Array("22 serialization::archive 10 0 7 0 7 30 Short".utf8)))
        XCTAssertNil(ArturiaPresetFile(bytes: []))
    }

    func testMatchingByNameKindAndValues() {
        let lead = ArturiaPresetFile(name: "Welcome", kind: "Dirty Lead", macroLabels: ["Timbre", "Time", "Deep", "FX"],
                                     macroValues: [0.628, 0, 0, 0.1], masterVolume: 0.636)
        let template = ArturiaPresetFile(name: "Welcome", kind: "Template", macroLabels: ["Timbre", "Time", "Unison", "Reverb"],
                                         macroValues: [0, 0, 0, 0], masterVolume: 0.673)
        let both = [lead, template]
        // The name alone leaves two presets with different labels.
        XCTAssertNil(ArturiaPresetMatch.macroLabels(among: both, name: "Welcome", kind: ""))
        // The type settles it.
        XCTAssertEqual(ArturiaPresetMatch.macroLabels(among: both, name: "Welcome", kind: "Template"), template.macroLabels)
        XCTAssertEqual(ArturiaPresetMatch.macroLabels(among: both, name: "Welcome", kind: "Dirty Lead"), lead.macroLabels)
        // So do the values, within 1 of the file's (0.673 × 127 is 85.5; 86 has been seen).
        XCTAssertEqual(ArturiaPresetMatch.macroLabels(among: both, name: "Welcome", kind: "", macroValues: [0, 0, 0, 0], volume: 86),
                       template.macroLabels)
        XCTAssertEqual(ArturiaPresetMatch.macroLabels(among: both, name: "Welcome", kind: "", macroValues: [80, nil, nil, nil]),
                       lead.macroLabels)
        // A type neither has is no filter; values that fit neither give nothing.
        XCTAssertNil(ArturiaPresetMatch.macroLabels(among: both, name: "Welcome", kind: "Pad"))
        XCTAssertNil(ArturiaPresetMatch.macroLabels(among: both, name: "Welcome", kind: "", macroValues: [40, 0, 0, 0]))
        // Presets that agree on their labels need no telling apart.
        var twin = lead
        twin.kind = "Pad"
        XCTAssertEqual(ArturiaPresetMatch.macroLabels(among: [lead, twin], name: "Welcome", kind: ""), lead.macroLabels)
        // No such name.
        XCTAssertNil(ArturiaPresetMatch.macroLabels(among: both, name: "Goodbye", kind: ""))
        XCTAssertNil(ArturiaPresetMatch.macroLabels(among: [], name: "Welcome", kind: ""))
    }

    func testANameIsSentCutTo15Characters() {
        XCTAssertTrue(ArturiaPresetMatch.name("Hang Me Some Melodies", matchesSent: "Hang Me Some Me"))
        XCTAssertTrue(ArturiaPresetMatch.name("Hanging Threads", matchesSent: "Hanging Threads"))
        XCTAssertFalse(ArturiaPresetMatch.name("Welcome Back", matchesSent: "Welcome"), "a short name is whole")
        XCTAssertFalse(ArturiaPresetMatch.name("Welcome", matchesSent: "Welcome Back"))
        let melodies = ArturiaPresetFile(name: "Hang Me Some Melodies", kind: "Bells", macroLabels: ["Timbre", "Pluck It", "Lo-Fi", "Delay"])
        XCTAssertEqual(ArturiaPresetMatch.macroLabels(among: [melodies], name: "Hang Me Some Me", kind: "Bells"), melodies.macroLabels)
    }

    func testParameterFiles() {
        let midi = """
            <rootnode>
            \t<midiconfig name="Default">
            \t\t<assignment controller="93" channel="0" paramid="9" min="0.000000" max="1.000000" isrelative="0"/>
            \t</midiconfig>
            \t<midiconfig name="KeyLab">
                    <assignment controller="16" paramid="3" isrelative="0" min="0.000000" max="1.000000" channel="0"/>
                    <assignment controller="17" paramid="0" isrelative="0" min="0.000000" max="1.000000" channel="0"/>
                    <assignment controller="74" paramid="1" isrelative="0" min="0.000000" max="1.000000" channel="0"/>
                    <assignment controller="93" paramid="2" isrelative="0" min="0.000000" max="1.000000" channel="0"/>
                    <assignment controller="85" paramid="40" isrelative="0" min="0.000000" max="1.000000" channel="0"/>
            \t</midiconfig>
            \t<midiconfig name="Other">
            \t\t<assignment controller="16" paramid="1" isrelative="0"/>
            \t</midiconfig>
            </rootnode>
            """
        let names = """
            <rootnode>
            <vst>
            <param name="Volume" display_name="Main Volume"/>
            <param name="M1" display_name="Macro 1"/>
            <param name="Cut" display_name="Cutoff"/>
            <param name="Res" display_name="Resonance"/>
            </vst>
            <other>
            <param name="X" display_name="Not This"/>
            </other>
            </rootnode>
            """
        XCTAssertEqual(ArturiaParameterFiles.assignments(inMIDIConfigurations: midi), [16: 3, 17: 0, 74: 1, 93: 2, 85: 40])
        XCTAssertEqual(ArturiaParameterFiles.assignments(inMIDIConfigurations: midi, configuration: "Default"), [93: 9])
        XCTAssertEqual(ArturiaParameterFiles.assignments(inMIDIConfigurations: midi, configuration: "Missing"), [:])
        XCTAssertEqual(ArturiaParameterFiles.displayNames(inParameterNames: names), ["Main Volume", "Macro 1", "Cutoff", "Resonance"])
        // A parameter number past the list has no name.
        XCTAssertEqual(ArturiaParameterFiles.names(midiConfigurations: midi, parameterNames: names),
                       [16: "Resonance", 17: "Main Volume", 74: "Macro 1", 93: "Cutoff"])
        XCTAssertEqual(ArturiaParameterFiles.names(midiConfigurations: "", parameterNames: names), [:])
        XCTAssertEqual(ArturiaParameterFiles.displayNames(inParameterNames: "<rootnode/>"), [])
    }
}
