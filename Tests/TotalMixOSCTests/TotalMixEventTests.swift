import XCTest
import OSCCodec
@testable import TotalMixOSC

final class TotalMixEventTests: XCTestCase {
    func testChannelSettings() {
        XCTAssertEqual(TotalMixEvent(OSCMessage("/input/2/mute", [.float(1)])),
                       .channel(bus: .input, channel: 2, parameter: "mute", value: .number(1)))
        XCTAssertEqual(TotalMixEvent(OSCMessage("/output/0/name", [.string("Main")])),
                       .channel(bus: .output, channel: 0, parameter: "name", value: .text("Main")))
        XCTAssertEqual(TotalMixEvent(OSCMessage("/playback/5/eq/band1gain", [.float(-3)])),
                       .channel(bus: .playback, channel: 5, parameter: "eq/band1gain", value: .number(-3)))
    }

    func testValuesSentAsBooleansOrIntegersAreNumbers() {
        XCTAssertEqual(TotalMixEvent(OSCMessage("/input/0/48v", [.bool(true)])),
                       .channel(bus: .input, channel: 0, parameter: "48v", value: .number(1)))
        XCTAssertEqual(TotalMixEvent(OSCMessage("/input/0/pad", [.int(0)])),
                       .channel(bus: .input, channel: 0, parameter: "pad", value: .number(0)))
    }

    func testMixerNodes() {
        XCTAssertEqual(TotalMixEvent(OSCMessage("/mix/in/0/2/faderlin", [.float(0.8)])),
                       .mix(bus: .input, channel: 0, output: 2, parameter: "faderlin", value: .number(Double(Float(0.8)))))
        XCTAssertEqual(TotalMixEvent(OSCMessage("/mix/pb/4/0/balpan", [.float(-1)])),
                       .mix(bus: .playback, channel: 4, output: 0, parameter: "balpan", value: .number(-1)))
    }

    func testLevelsAndSnapshots() {
        XCTAssertEqual(TotalMixEvent(OSCMessage("/level/out/1", [.float(-12.5)])),
                       .level(bus: .output, channel: 1, peakDB: -12.5))
        XCTAssertEqual(TotalMixEvent(OSCMessage("/snapshot/load/3", [.float(2)])),
                       .snapshot(number: 3, state: .active))
    }

    func testWrongSpellingsAreNotTakenForChannels() {
        // Channel settings spell the bus in full; "/in/2/mute" is not a channel address.
        XCTAssertEqual(TotalMixEvent(OSCMessage("/in/2/mute", [.float(1)])), .other(path: "in/2/mute", value: .number(1)))
        // Mixer nodes use "in" and "pb", not the full words.
        XCTAssertEqual(TotalMixEvent(OSCMessage("/mix/input/0/2/fader", [.float(0)])),
                       .other(path: "mix/input/0/2/fader", value: .number(0)))
        // Levels use "out" for outputs.
        XCTAssertEqual(TotalMixEvent(OSCMessage("/level/output/1", [.float(0)])),
                       .other(path: "level/output/1", value: .number(0)))
    }

    func testOtherMessages() {
        XCTAssertEqual(TotalMixEvent(OSCMessage("/controlroom/dim", [.float(1)])), .other(path: "controlroom/dim", value: .number(1)))
        XCTAssertEqual(TotalMixEvent(OSCMessage("/durec/state", [.string("Play")])), .other(path: "durec/state", value: .text("Play")))
        XCTAssertEqual(TotalMixEvent(OSCMessage("/status/device", [.string("Digiface AES")])),
                       .other(path: "status/device", value: .text("Digiface AES")))
        XCTAssertNil(TotalMixEvent(OSCMessage("/")))
    }

    func testCommands() {
        XCTAssertEqual(TotalMixCommand.set(.output, 2, "faderlin", 0.3), OSCMessage("/output/2/faderlin", [.float(0.3)]))
        XCTAssertEqual(TotalMixCommand.setMix(from: .input, 0, to: 2, "faderlin", 0.8), OSCMessage("/mix/in/0/2/faderlin", [.float(0.8)]))
        XCTAssertNil(TotalMixCommand.setMix(from: .output, 0, to: 2, "faderlin", 0.8))
        XCTAssertEqual(TotalMixCommand.sendChannel(.input, 2), OSCMessage("/sendchan/input/2", [.float(1)]))
        XCTAssertEqual(TotalMixCommand.sendAll(activeNodesOnly: true), OSCMessage("/sendall", [.float(2)]))
        XCTAssertEqual(TotalMixCommand.sendSubmix(4), OSCMessage("/sendsubmix/4", [.float(1)]))
        XCTAssertEqual(TotalMixCommand.loadSnapshot(2), OSCMessage("/snapshot/load/2", [.float(1)]))
    }

    func testBusSpellings() {
        XCTAssertEqual(TotalMixBus.playback.settingsName, "playback")
        XCTAssertEqual(TotalMixBus.playback.mixName, "pb")
        XCTAssertNil(TotalMixBus.output.mixName)
        XCTAssertEqual(TotalMixBus.output.levelName, "out")
        XCTAssertEqual(TotalMixBus(word: "pb"), .playback)
        XCTAssertNil(TotalMixBus(word: "main"))
    }

    func testGroupFlags() {
        // Outputs 3/4 and 7/8 in test 1: members of mute group 1, reporting 4098.
        let flags = TotalMixGroupFlags(4098)
        XCTAssertEqual(flags.muteGroups, [1])
        XCTAssertEqual(flags.soloGroups, [])
        XCTAssertEqual(flags.faderGroups, [1])
        XCTAssertEqual(TotalMixGroupFlags(rawValue: 0).muteGroups, [])
        // Every group: bits 1–4, 6–9, and 12–15.
        let all = TotalMixGroupFlags(rawValue: 0b1111_0011_1101_1110)
        XCTAssertEqual(all.muteGroups, [1, 2, 3, 4])
        XCTAssertEqual(all.soloGroups, [1, 2, 3, 4])
        XCTAssertEqual(all.faderGroups, [1, 2, 3, 4])
    }

    func testEndpointDefaults() {
        let endpoint = TotalMixEndpoint.standard
        XCTAssertEqual(endpoint.host, "localhost")
        XCTAssertEqual(endpoint.incomingPort, 7001)
        XCTAssertEqual(endpoint.outgoingPort, 9001)
    }
}
