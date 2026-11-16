import XCTest
import RotoControl
import ArturiaControl
@testable import ArturiaNameRelay

final class ArturiaNameRelayTests: XCTestCase {
    // The plugin's messages, in the KeyLab mk3's format; Analog Lab V's id is 1.
    private func connect(_ on: Bool = true, id: UInt8 = 1) -> [UInt8] {
        [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x00, id, 0x05, on ? 1 : 0, 0xF7]
    }
    private func value(_ item: UInt8, _ value: UInt8, id: UInt8 = 1) -> [UInt8] {
        ArturiaMk3Message.knobValue(item: Int(item), value: Int(value), id: Int(id))
    }
    private func preset(_ name: String, _ kind: String = "Classic Synth Keys", id: UInt8 = 1) -> [UInt8] {
        [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x00, id, 0x04, 0x10, 0x00] + Array(name.utf8) + [0x00, 0x01, 0x00, 0x00, 0x03]
            + Array(kind.utf8) + [0x00, 0x04, 0x00, 0x00, 0x05, 0x7F, 0x7F, 0x7F, 0x00, 0x06, 34, 0x00, 0xF7]
    }
    private func screen(_ name: String, _ valueText: String, value: UInt8, id: UInt8 = 1) -> [UInt8] {
        [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x00, id, 0x04, 0x1C, 0x00] + Array(valueText.utf8) + [0x00, 0x01]
            + Array(name.utf8) + [0x00, 0x02, value, 0x00, 0xF7]
    }

    // The host's messages, as Bitwig's integration lays them out.
    private func learn(_ number: Int, _ name: String, position: Int = 0) -> [UInt8] {
        RotoOutgoing.learnParameter(.macro(number, name: name, position: position)).bytes
    }
    private func mapped(_ number: Int, _ name: String) -> [UInt8] {
        RotoOutgoing.mappedControlName(parameterIndex: number, hash: .macroParameter(number), name: name).bytes
    }
    private func plugin(_ index: Int, _ name: String) -> [UInt8] {
        RotoOutgoing.pluginDetails(.macro(index: index, name: name, pages: 3)).bytes
    }
    private func select(_ index: Int, page: Int = 0) -> [UInt8] {
        RotoOutgoing.dawSelectPlugin(index: index, macroPage: page, force: false).bytes
    }

    private let hostNames = ["Brightness", "Timbre", "Time", "Movement", "FXA Dry/Wet", "FXB Dry/Wet", "Delay Volume", "Reverb Volume"]

    /// A relay in PLUGIN mode whose host has selected Analog Lab V and described its first page.
    private func relayWithHost(pluginName: String = "Analog Lab V", page: Int = 0) -> ArturiaNameRelay {
        var relay = ArturiaNameRelay()
        relay.isInPluginMode = true
        _ = relay.fromHost(RotoOutgoing.pluginCount(1).bytes, now: 0)
        _ = relay.fromHost(plugin(0, pluginName), now: 0)
        _ = relay.fromHost(select(0, page: page), now: 0)
        for (offset, name) in hostNames.enumerated() {
            _ = relay.fromHost(learn(offset + 1, ""), now: 0)
            _ = relay.fromHost(mapped(offset + 1, name), now: 0)
            _ = relay.fromHost(learn(offset + 1, name), now: 0)
        }
        return relay
    }

    /// The plugin connects as it was seen to: zeros first, the real values, then the preset.
    private func connectPlugin(_ relay: inout ArturiaNameRelay, at time: TimeInterval = 10) -> ArturiaNameRelayOutput {
        var output = relay.fromInstrument(connect(), now: time)
        for item in 0..<9 { output.add(relay.fromInstrument(value(UInt8(item), 0), now: time + 0.1)) }
        for (item, real) in [28, 54, 80, 0, 0, 0, 0, 25, 109].enumerated() {
            output.add(relay.fromInstrument(value(UInt8(item), UInt8(real)), now: time + 0.2))
        }
        output.add(relay.fromInstrument(preset("Classic Jun Keys"), now: time + 0.6))
        return output
    }

    func testHostMessagesPassUnchangedWithoutThePlugin() {
        var relay = ArturiaNameRelay()
        relay.isInPluginMode = true
        _ = relay.fromHost(plugin(0, "Analog Lab V"), now: 0)
        let selected = relay.fromHost(select(0), now: 0)
        XCTAssertEqual(selected.message, select(0))
        XCTAssertEqual(selected.output.toDevice, [])
        XCTAssertEqual(selected.output.notes.count, 1, "says that the plugin has not connected")
        let learned = relay.fromHost(learn(5, "FXA Dry/Wet", position: 300), now: 0)
        XCTAssertEqual(learned.message, learn(5, "FXA Dry/Wet", position: 300))
        XCTAssertEqual(learned.output, ArturiaNameRelayOutput())
        XCTAssertFalse(relay.isActive)
    }

    func testPresetNameIsSentOnceThePluginConnects() {
        var relay = relayWithHost()
        let output = connectPlugin(&relay)
        XCTAssertTrue(relay.isActive)
        XCTAssertEqual(output.toDevice, [RotoOutgoing.currentTrackName("Classic Jun Keys").bytes])
        XCTAssertEqual(output.toInstrument, [])
    }

    func testAsksOnlyAfterThePresetScreenAndWithTheRealValues() {
        var relay = relayWithHost()
        _ = relay.fromInstrument(connect(), now: 10)
        for item in 0..<9 { _ = relay.fromInstrument(value(UInt8(item), 0), now: 10.1) }
        XCTAssertEqual(relay.tick(now: 12).toInstrument, [], "no preset screen yet: the zeros are not trusted")
        _ = relay.fromInstrument(value(0, 28), now: 12.1)
        _ = relay.fromInstrument(preset("Classic Jun Keys"), now: 12.5)
        XCTAssertEqual(relay.tick(now: 12.7).toInstrument, [], "the plugin's messages have only just stopped")
        XCTAssertEqual(relay.tick(now: 13.1).toInstrument, [[0xB0, 74, 28]])
        XCTAssertEqual(relay.tick(now: 13.2).toInstrument, [], "one at a time")
    }

    func testAnAnswerRenamesTheKnobAndTheNextIsAsked() {
        var relay = relayWithHost()
        _ = connectPlugin(&relay)
        XCTAssertEqual(relay.tick(now: 11.2).toInstrument, [[0xB0, 74, 28]])
        let answer = relay.fromInstrument(screen("Brightness", "0.223", value: 28), now: 11.25)
        XCTAssertEqual(answer.toDevice, [], "the same name as the host's: nothing to send")
        XCTAssertEqual(relay.fromInstrument(screen("Brightness", "0.223", value: 28), now: 11.28).toDevice, [])
        XCTAssertEqual(relay.tick(now: 11.3).toInstrument, [], "waits for the answer's copies")
        XCTAssertEqual(relay.tick(now: 11.5).toInstrument, [[0xB0, 71, 54]])
        _ = relay.fromInstrument(screen("Timbre", "0.425", value: 54), now: 11.55)
        XCTAssertEqual(relay.tick(now: 11.8).toInstrument, [[0xB0, 76, 80]])
        _ = relay.fromInstrument(screen("Time", "0.630", value: 80), now: 11.85)
        XCTAssertEqual(relay.tick(now: 12.1).toInstrument, [[0xB0, 77, 0]])
        _ = relay.fromInstrument(screen("Movement", "0.00", value: 0), now: 12.15)
        XCTAssertEqual(relay.tick(now: 12.4).toInstrument, [[0xB0, 93, 0]])
        let effect = relay.fromInstrument(screen("Chorus Mix", "0 %", value: 0), now: 12.45)
        XCTAssertEqual(effect.toDevice, [mapped(5, "Chorus Mix")])
        XCTAssertEqual(relay.name(forItem: 4), "Chorus Mix")
    }

    func testHostNamesAreReplacedOnceKnown() {
        var relay = relayWithHost()
        _ = connectPlugin(&relay)
        // The keyboard's fifth encoder is turned, and the plugin answers it.
        relay.fromKeyboard([0xB0, 93, 70], now: 20)
        let answer = relay.fromInstrument(screen("Distortion Mix", "55 %", value: 70), now: 20.05)
        XCTAssertEqual(answer.toDevice, [mapped(5, RotoNameFit.fit("Distortion Mix"))])
        // The host describes the knob again: its name is replaced, the rest kept.
        let again = relay.fromHost(learn(5, "FXA Dry/Wet", position: 9000), now: 21)
        XCTAssertEqual(again.message, learn(5, RotoNameFit.fit("Distortion Mix"), position: 9000))
        XCTAssertEqual(again.output.toDevice, [])
        XCTAssertEqual(relay.fromHost(learn(6, "FXB Dry/Wet"), now: 21).message, learn(6, "FXB Dry/Wet"))
    }

    func testAnotherPresetRestoresTheHostNamesAndAsksAgain() {
        var relay = relayWithHost()
        _ = connectPlugin(&relay)
        relay.fromKeyboard([0xB0, 93, 70], now: 20)
        _ = relay.fromInstrument(screen("Chorus Mix", "55 %", value: 70), now: 20.05)
        let changed = relay.fromInstrument(preset("Classic Lead", "Solo Lead"), now: 30)
        XCTAssertEqual(changed.toDevice, [mapped(5, "FXA Dry/Wet"), RotoOutgoing.currentTrackName("Classic Lead").bytes])
        XCTAssertEqual(relay.tick(now: 31).toInstrument, [], "the new preset's values have not come")
        _ = relay.fromInstrument(value(4, 12), now: 31)
        XCTAssertEqual(relay.tick(now: 31.6).toInstrument, [[0xB0, 93, 12]])
    }

    func testTheSamePresetMarkedAsChangedKeepsTheNames() {
        var relay = relayWithHost()
        _ = connectPlugin(&relay)
        relay.fromKeyboard([0xB0, 93, 70], now: 20)
        _ = relay.fromInstrument(screen("Chorus Mix", "55 %", value: 70), now: 20.05)
        let marked = relay.fromInstrument(preset("Classic Jun Keys*"), now: 22)
        XCTAssertEqual(marked.toDevice, [])
        XCTAssertEqual(relay.name(forItem: 4), "Chorus Mix")
    }

    func testNothingIsPutInOnAnotherPageOrForAnotherPlugin() {
        var second = relayWithHost(page: 1)
        _ = connectPlugin(&second)
        XCTAssertFalse(second.isActive)
        XCTAssertEqual(second.tick(now: 12).toInstrument, [])

        var other = relayWithHost(pluginName: "Pigments")
        XCTAssertEqual(connectPlugin(&other).toDevice, [])
        XCTAssertFalse(other.isActive)

        var pigments = relayWithHost()
        _ = pigments.fromInstrument(connect(id: 13), now: 10)
        _ = pigments.fromInstrument(preset("Welcome", "Template", id: 13), now: 10.5)
        XCTAssertFalse(pigments.isActive, "the plugin on the KeyLab port is not Analog Lab V")
    }

    func testAPageChangeFromTheDeviceStopsTheNames() {
        var relay = relayWithHost()
        _ = connectPlugin(&relay)
        relay.fromKeyboard([0xB0, 93, 70], now: 20)
        _ = relay.fromInstrument(screen("Chorus Mix", "55 %", value: 70), now: 20.05)
        XCTAssertEqual(relay.fromDevice([0xF0, 0x00, 0x22, 0x03, 0x02, 0x0B, 0x10, 0x01, 0xF7], now: 25).toDevice, [])
        XCTAssertEqual(relay.fromHost(learn(5, "Env Amp Atk"), now: 25.1).message, learn(5, "Env Amp Atk"))
        // Back on the first page, the name is put in again.
        _ = relay.fromDevice([0xF0, 0x00, 0x22, 0x03, 0x02, 0x0B, 0x10, 0x00, 0xF7], now: 26)
        XCTAssertEqual(relay.fromHost(learn(5, "FXA Dry/Wet"), now: 26.1).message, learn(5, "Chorus Mix"))
    }

    func testAKnobTheUserTurnedIsNotAsked() {
        var relay = relayWithHost()
        _ = connectPlugin(&relay)
        _ = relay.fromDevice([0xBF, 12, 40], now: 10.7)
        XCTAssertEqual(relay.tick(now: 11.2).toInstrument, [[0xB0, 71, 54]], "knob 1 is skipped")
    }

    func testDisconnectingRestoresTheHostNames() {
        var relay = relayWithHost()
        _ = connectPlugin(&relay)
        relay.fromKeyboard([0xB0, 93, 70], now: 20)
        _ = relay.fromInstrument(screen("Chorus Mix", "55 %", value: 70), now: 20.05)
        XCTAssertEqual(relay.fromInstrument(connect(false), now: 30).toDevice, [mapped(5, "FXA Dry/Wet")])
        XCTAssertFalse(relay.isConnected)
    }

    func testNothingIsSentToTheDeviceInMixMode() {
        var relay = relayWithHost()
        relay.isInPluginMode = false
        XCTAssertEqual(connectPlugin(&relay).toDevice, [])
        XCTAssertEqual(relay.tick(now: 12).toInstrument, [])
    }
}
