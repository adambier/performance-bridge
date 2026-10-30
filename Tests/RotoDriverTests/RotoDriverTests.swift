import XCTest
import OSCCodec
import TotalMixOSC
import RotoControl
import SurfaceCore
@testable import RotoDriver

/// Inputs 1/2 ("Keys", stereo), 3 ("Vox"), 4 ("Gtr"); playbacks 1/2 ("Tracks", stereo);
/// outputs 1/2 ("Main") and 3/4 ("Phones"); Main Out on output 1; every node at 0.5.
private func loadedHub() -> SurfaceHub {
    var hub = SurfaceHub()
    var events: [TotalMixEvent] = []
    func channel(_ bus: TotalMixBus, _ number: Int, _ name: String, stereo: Bool) {
        events.append(.channel(bus: bus, channel: number, parameter: "stereo", value: .number(stereo ? 1 : 0)))
        events.append(.channel(bus: bus, channel: number, parameter: "name", value: .text(name)))
        events.append(.channel(bus: bus, channel: number, parameter: "color", value: .number(1)))
        events.append(.channel(bus: bus, channel: number, parameter: "mute", value: .number(0)))
        events.append(.channel(bus: bus, channel: number, parameter: "pfl", value: .number(0)))
    }
    channel(.input, 0, "Keys", stereo: true)
    channel(.input, 2, "Vox", stereo: false)
    channel(.input, 3, "Gtr", stereo: false)
    channel(.playback, 0, "Tracks", stereo: true)
    channel(.output, 0, "Main", stereo: true)
    channel(.output, 2, "Phones", stereo: true)
    events.append(.channel(bus: .output, channel: 0, parameter: "faderlin", value: .number(0.8)))
    events.append(.channel(bus: .output, channel: 2, parameter: "faderlin", value: .number(0.6)))
    for (bus, number) in [(TotalMixBus.input, 0), (.input, 2), (.input, 3), (.playback, 0)] {
        for output in [0, 2] {
            events.append(.mix(bus: bus, channel: number, output: output, parameter: "faderlin", value: .number(0.5)))
            events.append(.mix(bus: bus, channel: number, output: output, parameter: "balpan", value: .number(0)))
        }
    }
    events.append(.other(path: "controlroom/mainout", value: .number(0)))
    for event in events { _ = hub.handle(event, now: 0) }
    return hub
}

private let rotoID = SurfaceID("roto")

private func sysEx(_ group: RotoCommandGroup, _ command: UInt8, _ data: [UInt8] = []) -> [UInt8] {
    RotoSysEx.frame(group, command, data)
}

private func cc(_ controller: UInt8, _ value: UInt8) -> [UInt8] { [0xBF, controller, value] }

private func knobCCs(_ index: Int, _ position: Int) -> [UInt8] {
    let bytes = RotoSysEx.encode14(position)
    return cc(RotoCC.knobHigh + UInt8(index), bytes[0]) + cc(RotoCC.knobLow + UInt8(index), bytes[1])
}

private let bitwigIndent = RotoDriver.unityIndent(for: .bitwig)

/// The 14-bit knob position the driver sends for a level's fader position.
private func levelKnob(_ fader: Double) -> Int {
    RotoFeedback.position(RotoDriver.knobPosition(forFader: fader, indent: bitwigIndent))
}

private extension Array where Element == UInt8 {
    func contains(_ part: [UInt8]) -> Bool {
        guard !part.isEmpty, part.count <= count else { return part.isEmpty }
        return (0...(count - part.count)).contains { Array(self[$0..<$0 + part.count]) == part }
    }

    func occurrences(_ part: [UInt8]) -> Int {
        guard !part.isEmpty, part.count <= count else { return 0 }
        return (0...(count - part.count)).filter { Array(self[$0..<$0 + part.count]) == part }.count
    }
}

/// A hub with the Roto-Control added, and a driver through the handshake.
private func connected() -> (driver: RotoDriver, hub: SurfaceHub, midi: [UInt8]) {
    var hub = loadedHub()
    _ = hub.addSurface(rotoID, capabilities: RotoDriver.capabilities, now: 0)
    var driver = RotoDriver(id: rotoID)
    _ = driver.start()
    _ = driver.receive(sysEx(.general, 0x02), hub: &hub, now: 0)
    let step = driver.receive(sysEx(.general, 0x0C), hub: &hub, now: 0)
    return (driver, hub, step.midi)
}

final class RotoDriverTests: XCTestCase {
    func testHandshakeClaimsBitwig() {
        var hub = loadedHub()
        var driver = RotoDriver(id: rotoID)
        XCTAssertEqual(driver.start(), RotoOutgoing.dawStarted.bytes)
        let ping = driver.receive(sysEx(.general, 0x02), hub: &hub, now: 0)
        XCTAssertEqual(ping.midi, RotoOutgoing.pingResponse(.bitwig).bytes)
        XCTAssertFalse(driver.isConnected)
    }

    func testConnectingDrawsEveryStrip() {
        let (driver, _, midi) = connected()
        XCTAssertTrue(driver.isConnected)
        XCTAssertTrue(midi.contains(RotoOutgoing.meterThresholds(yellow: 126, red: 127).bytes))
        XCTAssertTrue(midi.contains(RotoOutgoing.trackCount(4).bytes))
        XCTAssertTrue(midi.contains(RotoOutgoing.trackDetails(RotoTrackDetails(index: 2, name: "Gtr", colorScheme: 0),
                                                              immediate: false).bytes))
        XCTAssertTrue(midi.contains(RotoOutgoing.trackDetailsEnd.bytes))
        for blank in 4..<8 {
            XCTAssertTrue(midi.contains(RotoOutgoing.resetTrackDetails(blank).bytes), "strip \(blank + 1) is blanked")
        }
        XCTAssertTrue(midi.contains(RotoFeedback.knob(1, position: levelKnob(0.5))))
        XCTAssertTrue(midi.contains(RotoFeedback.switchLight(3, on: false)))
    }

    func testNothingIsSentBeforeTheHandshake() {
        var hub = loadedHub()
        _ = hub.addSurface(rotoID, capabilities: RotoDriver.capabilities, now: 0)
        var driver = RotoDriver(id: rotoID)
        let step = driver.receive(knobCCs(1, 4000), hub: &hub, now: 1)
        XCTAssertEqual(step, RotoStep())
        XCTAssertTrue(driver.render([.knob(index: 0, value: 0.5)], hub: hub).isEmpty)
    }

    func testTurningAKnobSetsTheNode() {
        var (driver, hub, _) = connected()
        let step = driver.receive(knobCCs(1, 4096), hub: &hub, now: 1)
        XCTAssertEqual(step.core.messages.map(\.address), ["/mix/in/2/0/faderlin"])
        XCTAssertFalse(step.midi.contains(RotoFeedback.knob(1, position: 4096)), "no echo to the knob turned")
        let fader = RotoDriver.faderPosition(forKnob: RotoFeedback.fraction(4096), indent: bitwigIndent)
        XCTAssertEqual(step.core.messages.first?.arguments, [.float(Float(fader))])
        let text = ValueText.level(position: fader)
        XCTAssertTrue(step.midi.contains(RotoOutgoing.showValue(.knob, control: 1, text: text).bytes))
    }

    func testAnEndEventIsIgnoredAndTheKnobPutBack() {
        var (driver, hub, _) = connected()
        _ = driver.receive(knobCCs(1, 200), hub: &hub, now: 1)
        let jump = driver.receive(knobCCs(1, 13026), hub: &hub, now: 2)
        XCTAssertTrue(jump.core.messages.isEmpty)
        XCTAssertTrue(jump.midi.contains(RotoFeedback.knob(1, position: 200)))
    }

    func testSwitchPressTogglesMuteAndLightsIt() {
        var (driver, hub, _) = connected()
        let press = driver.receive(cc(RotoCC.switchFirst + 2, 127), hub: &hub, now: 1)
        XCTAssertEqual(press.core.messages, [TotalMixCommand.set(.input, 3, "mute", 1)])
        XCTAssertTrue(press.midi.contains(RotoFeedback.switchLight(2, on: true)))
        XCTAssertEqual(driver.receive(cc(RotoCC.switchFirst + 2, 0), hub: &hub, now: 1.1), RotoStep(),
                       "a release does nothing")
    }

    func testModesMapOntoTheCore() {
        var (driver, hub, _) = connected()
        // SET MIX ALL TRACKS MODE: audio tracks, pan, record arm, send 0.
        let step = driver.receive(sysEx(.mix, 0x01, [0x00, 0x01, 0x02, 0x00]), hub: &hub, now: 1)
        XCTAssertEqual(hub.mode(of: rotoID), .strips(view: .sources, first: 0, knob: .pan, switch: .pfl))
        XCTAssertEqual(step.midi.occurrences([0xBF, RotoCC.knobHigh + 0]), 1, "knob positions are sent again")
        XCTAssertTrue(step.midi.contains(RotoFeedback.knob(3, position: RotoFeedback.position(0.5))))
        let press = driver.receive(cc(RotoCC.switchFirst, 127), hub: &hub, now: 2)
        XCTAssertEqual(press.core.messages, [TotalMixCommand.set(.input, 0, "pfl", 1)], "arm is PFL")
    }

    func testSendModeSendsTheSendNames() {
        var (driver, hub, _) = connected()
        let step = driver.receive(sysEx(.mix, 0x01, [0x00, 0x02, 0x00, 0x00]), hub: &hub, now: 1)
        XCTAssertEqual(hub.mode(of: rotoID), .strips(view: .sources, first: 0, knob: .send(0), switch: .mute))
        XCTAssertTrue(step.midi.contains(RotoOutgoing.sendCount(1).bytes))
        XCTAssertTrue(step.midi.contains(RotoOutgoing.sendNames(start: 0, names: ["to Phones"]).bytes))
        let turn = driver.receive(knobCCs(0, 6000), hub: &hub, now: 2)
        XCTAssertEqual(turn.core.messages.map(\.address), ["/mix/in/0/2/faderlin"])
    }

    func testSendLabels() {
        XCTAssertEqual(RotoDriver.sendLabel("Phones"), "to Phones")
        XCTAssertEqual(RotoDriver.sendLabel("ADI-2 +6dB"), "> ADI-2 +6dB")
        XCTAssertEqual(RotoDriver.sendLabel("Headphone Amp"), ">Headphone A")
        XCTAssertEqual(RotoDriver.sendLabel(""), "to ")
    }

    func testSendNamesGoOutInEveryKnobMode() {
        let (_, _, midi) = connected()
        XCTAssertTrue(midi.contains(RotoOutgoing.sendNames(start: 0, names: ["to Phones"]).bytes),
                      "level mode too, so the names shown while SEL is held are current")
    }

    func testRequestedSendNames() {
        var (driver, hub, _) = connected()
        let step = driver.receive(sysEx(.mix, 0x07, [0x00]), hub: &hub, now: 1)
        XCTAssertEqual(step.midi, RotoOutgoing.sendNames(start: 0, names: ["to Phones"]).bytes)
    }

    func testTheSecondTrackSetIsTheOutputs() {
        var (driver, hub, _) = connected()
        let step = driver.receive(sysEx(.mix, 0x05, [0x01]), hub: &hub, now: 1)
        XCTAssertEqual(hub.mode(of: rotoID), .strips(view: .outputs, first: 0, knob: .level, switch: .mute))
        XCTAssertTrue(step.midi.contains(RotoOutgoing.trackCount(2).bytes))
        XCTAssertTrue(step.midi.contains(RotoOutgoing.trackDetails(RotoTrackDetails(index: 0, name: "Main", colorScheme: RotoDriver.monitoringScheme),
                                                                   immediate: false).bytes), "Main is green")
        XCTAssertTrue(step.midi.contains(RotoOutgoing.trackDetails(RotoTrackDetails(index: 1, name: "Phones", colorScheme: RotoDriver.sendScheme),
                                                                   immediate: false).bytes), "unassigned in the control room: a send, blue")
        XCTAssertTrue(step.midi.contains(RotoFeedback.knob(1, position: levelKnob(0.6))))
        let turn = driver.receive(knobCCs(0, 9000), hub: &hub, now: 2)
        XCTAssertEqual(turn.core.messages.map(\.address), ["/output/0/faderlin"])
    }

    func testSingleTrackModeFocusesTheSelectedTrack() {
        var (driver, hub, _) = connected()
        _ = driver.receive(sysEx(.general, 0x09, RotoSysEx.encode14(1)), hub: &hub, now: 1)
        let step = driver.receive(sysEx(.mix, 0x02, [0x00]), hub: &hub, now: 2)
        let vox = ChannelRef(.input, 2)
        XCTAssertEqual(hub.mode(of: rotoID), .focus(channel: vox, first: 0))
        XCTAssertTrue(step.midi.contains(RotoOutgoing.sendNames(start: 0, names: ["to Phones"]).bytes))
        XCTAssertTrue(step.midi.contains(RotoOutgoing.selectTrack(RotoTrackDetails(index: 1, name: "Vox", colorScheme: 0)).bytes))
        let send = driver.receive(knobCCs(2, 3000), hub: &hub, now: 3)
        XCTAssertEqual(send.core.messages.map(\.address), ["/mix/in/2/2/faderlin"], "knob 3 is the first send")
        let page1 = driver.receive(sysEx(.mix, 0x02, [0x01]), hub: &hub, now: 4)
        XCTAssertEqual(hub.mode(of: rotoID), .focus(channel: vox, first: 0), "only one send: no second page")
        XCTAssertTrue(page1.midi.contains(RotoOutgoing.selectTrack(RotoTrackDetails(index: 1, name: "Vox", colorScheme: 0)).bytes))
    }

    func testPagingFromTheRotoControl() {
        var (driver, hub, _) = connected()
        let step = driver.receive(sysEx(.general, 0x06, RotoSysEx.encode14(8)), hub: &hub, now: 1)
        XCTAssertEqual(hub.mode(of: rotoID), .standard, "four sources: page 8 is past the end, so it stays")
        XCTAssertTrue(step.midi.contains(RotoOutgoing.firstTrack(0).bytes))
    }

    func testPluginModeLeavesTheMixerAlone() {
        var (driver, hub, _) = connected()
        let enter = driver.receive(sysEx(.plugin, 0x01, [0x00]), hub: &hub, now: 1)
        XCTAssertEqual(enter.midi, [RotoOutgoing.pluginCount(0), .firstPlugin(0), .pluginDetailsEnd].flatMap(\.bytes))
        XCTAssertEqual(driver.receive(knobCCs(1, 8191), hub: &hub, now: 2), RotoStep())
        XCTAssertTrue(driver.render([.knob(index: 1, value: 0.2)], hub: hub).isEmpty)
        _ = driver.receive(sysEx(.mix, 0x01, [0x00, 0x00, 0x00, 0x00]), hub: &hub, now: 3)
        XCTAssertFalse(driver.receive(knobCCs(1, 8000), hub: &hub, now: 4).core.messages.isEmpty, "back in MIX mode")
    }

    func testOtherSurfacesGetTheirUpdates() {
        var (driver, hub, _) = connected()
        let other = SurfaceID("other")
        _ = hub.addSurface(other, capabilities: RotoDriver.capabilities, now: 0)
        let step = driver.receive(knobCCs(1, 4096), hub: &hub, now: 1)
        XCTAssertNotNil(step.core.updates[other])
        XCTAssertNil(step.core.updates[rotoID], "the driver's own updates are already MIDI")
    }

    func testMetersAndValuesFromTheHub() {
        var (driver, hub, _) = connected()
        let output = hub.handle(.level(bus: .input, channel: 2, peakDB: -30), now: 1)
        let midi = driver.render(output.updates[rotoID] ?? [], hub: hub)
        let value = UInt8(MeterScale.value(peakDB: -30))
        XCTAssertEqual(midi, RotoFeedback.meter(1, left: value, right: value))
    }

    func testTransportStatusIsAnswered() {
        var (driver, hub, _) = connected()
        let step = driver.receive(sysEx(.general, 0x0A), hub: &hub, now: 1)
        XCTAssertEqual(step.midi, RotoOutgoing.transportStatus(RotoTransportStatus()).bytes)
    }

    func testAPingAfterConnectingStartsOver() {
        var (driver, hub, _) = connected()
        _ = driver.receive(sysEx(.general, 0x02), hub: &hub, now: 1)
        XCTAssertFalse(driver.isConnected)
        XCTAssertEqual(driver.receive(knobCCs(1, 4000), hub: &hub, now: 2), RotoStep())
    }

    func testValuesFromTheRotoControlAtTheirExtremes() {
        var (driver, hub, _) = connected()
        for index in [0, 7] {
            for position in [0, 16383] { _ = driver.receive(knobCCs(index, position), hub: &hub, now: 5) }
            _ = driver.receive(cc(RotoCC.switchFirst + UInt8(index), 127), hub: &hub, now: 6)
            _ = driver.receive(cc(RotoCC.touchFirst + UInt8(index), 127), hub: &hub, now: 6)
        }
        _ = driver.receive(sysEx(.general, 0x06, RotoSysEx.encode14(16383)), hub: &hub, now: 7)
        _ = driver.receive(sysEx(.general, 0x09, RotoSysEx.encode14(16383)), hub: &hub, now: 7)
        _ = driver.receive(sysEx(.mix, 0x02, [0x7F]), hub: &hub, now: 8)
        _ = driver.receive(sysEx(.mix, 0x01, [0x00, 0x02, 0x00, 0x7F]), hub: &hub, now: 9)
        _ = driver.receive(sysEx(.mix, 0x07, [0x7F]), hub: &hub, now: 9)
        XCTAssertEqual(hub.mode(of: rotoID), .strips(view: .sources, first: 0, knob: .send(127), switch: .mute))
        XCTAssertNil(hub.strips(of: rotoID)?[0].knobTarget, "send 128 does not exist")
        XCTAssertTrue(driver.render([.strip(index: 99, info: nil), .meter(index: 7, value: 500)], hub: hub)
                        .contains(RotoFeedback.meter(7, left: 127, right: 127)))
    }

    func testTheIndentIsTotalMixsZeroDecibels() {
        let indent = bitwigIndent ?? .nan
        XCTAssertEqual(indent, 0.7937, accuracy: 1e-4)
        XCTAssertEqual(RotoDriver.knobPosition(forFader: FaderCurve.unityPosition, indent: indent), indent, accuracy: 1e-12)
        XCTAssertEqual(RotoDriver.faderPosition(forKnob: indent, indent: indent), FaderCurve.unityPosition, accuracy: 1e-12)
        for end in [0.0, 1.0] {
            XCTAssertEqual(RotoDriver.knobPosition(forFader: end, indent: indent), end)
            XCTAssertEqual(RotoDriver.faderPosition(forKnob: end, indent: indent), end)
        }
        for step in 0...100 {
            let fader = Double(step) / 100
            XCTAssertEqual(RotoDriver.faderPosition(forKnob: RotoDriver.knobPosition(forFader: fader, indent: indent), indent: indent),
                           fader, accuracy: 1e-12)
        }
        XCTAssertEqual(RotoDriver.knobPosition(forFader: 0.3, indent: nil), 0.3, "no indent, no bend")
        XCTAssertEqual(RotoDriver.knobPosition(forFader: -1, indent: indent), 0)
        XCTAssertEqual(RotoDriver.faderPosition(forKnob: 2, indent: indent), 1)
        XCTAssertNil(RotoDriver.unityIndent(for: .logic))
        XCTAssertEqual(RotoDriver.unityIndent(for: .ableton) ?? 0, 13926.0 / 16383, accuracy: 1e-12)
    }

    func testTurningIntoTheIndentSetsZeroDecibels() {
        var (driver, hub, _) = connected()
        let indentCount = RotoFeedback.position(bitwigIndent ?? 0)
        let step = driver.receive(knobCCs(1, indentCount), hub: &hub, now: 1)
        guard case .float(let sent)? = step.core.messages.first?.arguments.first else { return XCTFail("no message") }
        XCTAssertEqual(FaderCurve.gainDB(position: Double(sent)) ?? .nan, 0, accuracy: 0.03)
        XCTAssertTrue(step.midi.contains(RotoOutgoing.showValue(.knob, control: 1, text: "0.0 dB").bytes))
    }

    func testPanKnobsAreNotBent() {
        var (driver, hub, _) = connected()
        let step = driver.receive(sysEx(.mix, 0x01, [0x00, 0x01, 0x00, 0x00]), hub: &hub, now: 1)
        XCTAssertTrue(step.midi.contains(RotoFeedback.knob(1, position: RotoFeedback.position(0.5))), "center pan is the center")
        let turn = driver.receive(knobCCs(1, 12288), hub: &hub, now: 2)
        guard case .float(let sent)? = turn.core.messages.first?.arguments.first else { return XCTFail("no message") }
        XCTAssertEqual(Double(sent), RotoFeedback.fraction(12288) * 2 - 1, accuracy: 1e-6)
    }

    func testColorSchemePlaceholder() {
        XCTAssertEqual(RotoDriver.colorScheme(forTotalMixColor: nil), 0)
        XCTAssertEqual(RotoDriver.colorScheme(forTotalMixColor: 1), 0)
        XCTAssertEqual(RotoDriver.colorScheme(forTotalMixColor: 2), 11)
        XCTAssertLessThanOrEqual(RotoDriver.colorScheme(forTotalMixColor: Int.max / 20), 82)
    }
}
