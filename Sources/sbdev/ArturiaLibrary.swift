// Reads, for `sbdev arturia`, the files Arturia's instruments install and keep, to name knobs
// before they are turned: an instrument's factory MIDI assignments and parameter names, and its
// preset files' macro labels (docs/ARTURIA.md, section 4). Read-only: nothing here writes.

import Foundation
import ArturiaControl

/// The folder Arturia's instruments are installed under, read lazily and only for instruments
/// whose files have been checked against what the instrument sends.
final class ArturiaLibrary {
    /// The instruments whose files' meaning has been checked on a device (docs/ARTURIA.md, tests
    /// 4 and 7): that the parameter numbers are positions in the name list, and that macros 1–4
    /// are control changes 74, 71, 76, and 77.
    static let checkedInstruments: Set<String> = ["Pigments"]

    let root: URL
    /// Whether to read files for instruments not in `checkedInstruments` too (`--trust-files`).
    let trustsUnchecked: Bool
    /// For each instrument, its preset files by file name, listed once.
    private var presetPaths: [String: [String: [URL]]] = [:]

    init(root: String, trustsUnchecked: Bool) {
        self.root = URL(fileURLWithPath: root, isDirectory: true)
        self.trustsUnchecked = trustsUnchecked
    }

    func reads(_ instrument: String) -> Bool {
        trustsUnchecked || Self.checkedInstruments.contains(instrument)
    }

    /// Each control change's parameter name in the instrument's "KeyLab" MIDI configuration, or
    /// none if the files are not there.
    func parameterNames(instrument: String) -> [Int: String] {
        guard reads(instrument) else { return [:] }
        let resources = root.appendingPathComponent(instrument).appendingPathComponent("resources")
        guard let assignments = try? String(contentsOf: resources.appendingPathComponent("plugin.prefmidi.xml"), encoding: .utf8),
              let names = try? String(contentsOf: resources.appendingPathComponent("Reference_ParamNames.xml"), encoding: .utf8) else {
            return [:]
        }
        return ArturiaParameterFiles.names(midiConfigurations: assignments, parameterNames: names)
    }

    /// The instrument's preset files (factory and user) by file name. A preset's file has been
    /// seen to be named as the preset is (all 9,392 of Pigments' factory presets).
    private func paths(instrument: String) -> [String: [URL]] {
        if let known = presetPaths[instrument] { return known }
        var found: [String: [URL]] = [:]
        let presets = root.appendingPathComponent("Presets").appendingPathComponent(instrument)
        for folder in ["Factory", "User"] {
            guard let files = FileManager.default.enumerator(at: presets.appendingPathComponent(folder),
                                                             includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                found[file.lastPathComponent, default: []].append(file)
            }
        }
        presetPaths[instrument] = found
        return found
    }

    /// The instrument's preset files whose names fit a preset's name as sent, read.
    /// If none fits, the folder is listed again once, for a preset added since.
    func presets(instrument: String, sentName: String, nameIsWhole: Bool = false) -> [(file: URL, preset: ArturiaPresetFile)] {
        guard reads(instrument) else { return [] }
        func fitting() -> [URL] {
            paths(instrument: instrument).filter { ArturiaPresetMatch.name($0.key, matchesSent: sentName, isWhole: nameIsWhole) }.flatMap(\.value)
        }
        var files = fitting()
        if files.isEmpty {
            presetPaths[instrument] = nil
            files = fitting()
        }
        return files.sorted { $0.path < $1.path }.compactMap { file in
            (try? Data(contentsOf: file)).flatMap { ArturiaPresetFile(bytes: [UInt8]($0)) }.map { (file, $0) }
        }
    }

    /// The loaded preset's macro labels, with how many files were read, or `nil` labels if no
    /// file matches or the matches differ.
    func macroLabels(instrument: String, preset: String, kind: String, macroValues: [Int?], volume: Int?,
                     nameIsWhole: Bool = false) -> (labels: [String?]?, read: Int) {
        let candidates = presets(instrument: instrument, sentName: preset, nameIsWhole: nameIsWhole).map(\.preset)
        return (ArturiaPresetMatch.macroLabels(among: candidates, name: preset, kind: kind, macroValues: macroValues, volume: volume,
                                               nameIsWhole: nameIsWhole),
                candidates.count)
    }
}

let arturiaFilesUsage = """
    Usage: sbdev arturia-files [--library PATH] INSTRUMENT [PRESET [TYPE]]
        Prints what `sbdev arturia` would read from an instrument's files, with no MIDI: the
        parameter names of its "KeyLab" MIDI configuration, and, with PRESET (the preset's name
        as the instrument sends it: at most 15 characters), each preset file of that name and
        the macro labels chosen, by TYPE too if given. Reads any instrument's files; nothing is
        written. E.g.: sbdev arturia-files Pigments "Hang Me Some Me" Bells
    """

func arturiaFiles(_ arguments: ArraySlice<String>) -> Never {
    var rest = arguments
    var root = "/Library/Arturia"
    var words: [String] = []
    while let argument = rest.popFirst() {
        switch argument {
        case "--library":
            guard let path = rest.popFirst() else { fail("--library needs a path.\n\n\(arturiaFilesUsage)") }
            root = path
        case "-h", "--help": print(arturiaFilesUsage); exit(0)
        default: words.append(argument)
        }
    }
    guard let instrument = words.first, words.count <= 3 else { fail(arturiaFilesUsage) }
    let library = ArturiaLibrary(root: root, trustsUnchecked: true)
    let names = library.parameterNames(instrument: instrument)
    if names.isEmpty {
        print("No parameter names read for \"\(instrument)\" under \(root).")
    } else {
        print("Parameter names of \"\(instrument)\" in its \"KeyLab\" MIDI configuration:")
        for (controller, name) in names.sorted(by: { $0.key < $1.key }) { print("  CC \(controller)  \(name)") }
    }
    if words.count >= 2 {
        let kind = words.count == 3 ? words[2] : ""
        for (file, preset) in library.presets(instrument: instrument, sentName: words[1]) {
            let labels = preset.macroLabels.map { $0.map { "\"\($0)\"" } ?? "-" }.joined(separator: ", ")
            print("\(file.path)\n  \"\(preset.name)\", type \"\(preset.kind)\", macro labels \(labels)")
        }
        let found = library.macroLabels(instrument: instrument, preset: words[1], kind: kind, macroValues: [nil, nil, nil, nil], volume: nil)
        let chosen = found.labels.map { $0.map { $0 ?? "-" }.joined(separator: ", ") } ?? "none (no file, or files that differ)"
        print("Macro labels chosen from \(found.read) file\(found.read == 1 ? "" : "s"): \(chosen)")
    }
    exit(0)
}
