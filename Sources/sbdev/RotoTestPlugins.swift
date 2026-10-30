// Plugins and parameters that `sbdev roto` offers in PLUGIN mode, for testing. They are stand-ins
// for parts of TotalMix FX; nothing here talks to TotalMix.

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
