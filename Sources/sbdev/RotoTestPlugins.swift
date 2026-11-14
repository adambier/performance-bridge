// Plugins and parameters that `sbdev roto` offers in PLUGIN mode, for testing. They are stand-ins
// for parts of TotalMix FX; nothing here talks to TotalMix FX.

import Foundation
import RotoControl

struct TestParameter {
    let name: String
    var position: Int
    var centerIndent = false
    var steps = 0
    var stepNames: [String] = []
}

struct TestPlugin {
    let name: String
    var parameters: [TestParameter]

    var hash: RotoHash { RotoHash.of("sbdev plugin " + name, length: 8) }

    func parameterHash(_ index: Int) -> RotoHash {
        RotoHash.of("sbdev parameter " + name + " / " + parameters[index].name, length: 6)
    }

    func details(index: Int) -> RotoPluginDetails {
        RotoPluginDetails(index: index, hash: hash, name: name)
    }

    func parameterDetails(_ index: Int) -> RotoParameterDetails {
        let parameter = parameters[index]
        return RotoParameterDetails(index: index, hash: parameterHash(index), name: parameter.name,
                                    position: parameter.position, centerIndent: parameter.centerIndent,
                                    steps: parameter.steps, stepNames: parameter.stepNames)
    }
}

let testPlugins: [TestPlugin] = [
    TestPlugin(name: "Ctrl Room", parameters: [
        TestParameter(name: "Main Vol", position: 13388),
        TestParameter(name: "Phones 1", position: 13388),
        TestParameter(name: "Phones 2", position: 13388),
        TestParameter(name: "Dim", position: 0, steps: 2, stepNames: ["Off", "On"]),
        TestParameter(name: "Main Out", position: 0, steps: 4, stepNames: ["Main", "Main B", "Phones 1", "Phones 2"]),
    ]),
    TestPlugin(name: "Ch EQ", parameters: [
        TestParameter(name: "Gain 1", position: 8192, centerIndent: true),
        TestParameter(name: "Freq 1", position: 4000),
        TestParameter(name: "Q 1", position: 6000),
        TestParameter(name: "Type 1", position: 0, steps: 3, stepNames: ["Peak", "Shelf", "Cut"]),
        TestParameter(name: "Gain 2", position: 8192, centerIndent: true),
        TestParameter(name: "EQ On", position: 16383, steps: 2, stepNames: ["Off", "On"]),
    ]),
    TestPlugin(name: "Ch Dynamics", parameters: [
        TestParameter(name: "Threshold", position: 12000),
        TestParameter(name: "Ratio", position: 4000, steps: 20),
        TestParameter(name: "Attack", position: 3000),
        TestParameter(name: "Release", position: 5000),
    ]),
    TestPlugin(name: "Ch Input", parameters: [
        TestParameter(name: "Gain", position: 0),
        TestParameter(name: "48V", position: 0, steps: 2, stepNames: ["Off", "On"]),
        TestParameter(name: "Pad", position: 0, steps: 2, stepNames: ["Off", "On"]),
        TestParameter(name: "Phase", position: 0, steps: 2, stepNames: ["Off", "On"]),
        TestParameter(name: "Pan", position: 8192, centerIndent: true),
    ]),
]

/// The one macro plugin `sbdev roto`'s `macro` command offers, for test R1 (docs/PLUGIN-MODE-PLAN.md):
/// whether the Roto-Control shows eight named, positioned knobs with no learning on the device.
/// With `wait`, the message sequence follows a reading of Melbourne Instruments' Bitwig
/// integration; without it, LEARN PARAM is sent unasked, which is this project's own variant.
/// Both are untested on the device.
struct MacroTest {
    /// The plugin's name on the device.
    static let pluginName = "Macro Test"
    /// Eight names for each page; a page past the second shows "P3 M1" and so on.
    static let pageNames: [[String]] = [
        ["Cutoff", "Reso", "Drive", "Attack", "Decay", "Sustain", "Release", "Volume"],
        ["LFO Rate", "LFO Depth", "Chorus", "Delay", "Reverb", "Width", "Glide", "Tune"],
    ]

    /// The number of macro pages declared in PLUGIN DETAILS.
    var pages: Int
    /// Whether LEARN PARAM is sent only in answer to CONTROL MAPPED (`macro --wait`), which is
    /// the order of Bitwig's integration.
    var wait: Bool
    /// The page the device last reported with MACRO PLUGIN PAGE INDEX.
    var page = 0
    /// Each page's eight names.
    var names: [[String]]
    /// Each page's eight positions (0–16383).
    var positions: [[Int]]

    init(pages: Int, wait: Bool) {
        self.pages = pages
        self.wait = wait
        let count = max(pages, 1)
        names = (0..<count).map { page in
            page < Self.pageNames.count ? Self.pageNames[page] : (1...8).map { "P\(page + 1) M\($0)" }
        }
        // Eight distinct positions, rising on the first page and falling on the second, so that
        // the knobs move on a page change.
        positions = (0..<count).map { page in
            (0..<8).map { RotoFeedback.position(Double(page % 2 == 0 ? $0 + 1 : 8 - $0) / 9) }
        }
    }

    /// The page as an index into `names` and `positions` (the device's value, kept in range).
    var pageIndex: Int { min(max(page, 0), names.count - 1) }

    /// PLUGIN DETAILS for the plugin, at index 0.
    var details: RotoPluginDetails {
        .macro(index: 0, name: Self.pluginName, pages: pages)
    }

    /// LEARN PARAM's details for macro `number` (1–8) of the current page.
    func parameter(_ number: Int) -> RotoParameterDetails {
        .macro(number, name: names[pageIndex][number - 1], position: positions[pageIndex][number - 1])
    }
}
