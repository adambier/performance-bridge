import XCTest
import OSCCodec
import TotalMixOSC
import LaunchControl
import SurfaceCore
@testable import LaunchControlDriver

/// Inputs 1/2 ("Keys", stereo), 3 ("Vox"), 4 ("Gtr"); playbacks 1/2 ("Tracks", stereo);
/// outputs 1/2 ("Main") and 3/4 ("Phones"); Main Out on output 1; every node at 0.5, centered.
/// The send targets are then output 3/4 alone.
private func loadedHub() -> SurfaceHub {
    var hub = SurfaceHub()
    var events: [TotalMixEvent] = []
    func channel(_ bus: TotalMixBus, _ number: Int, _ name: String, stereo: Bool, color: Int = 1) {
        events.append(.channel(bus: bus, channel: number, parameter: "stereo", value: .number(stereo ? 1 : 0)))
        events.append(.channel(bus: bus, channel: number, parameter: "name", value: .text(name)))
        events.append(.channel(bus: bus, channel: number, parameter: "color", value: .number(Double(color))))
        events.append(.channel(bus: bus, channel: number, parameter: "mute", value: .number(0)))
        events.append(.channel(bus: bus, channel: number, parameter: "pfl", value: .number(0)))
    }
    channel(.input, 0, "Keys", stereo: true, color: 4)
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

private extension Array where Element == UInt8 {
    func contains(_ part: [UInt8]) -> Bool {
        guard !part.isEmpty, part.count <= count else { return part.isEmpty }
        return (0...(count - part.count)).contains { Array(self[$0..<$0 + part.count]) == part }
    }
}

/// Adds stereo outputs, as further send targets.
private func addOutputs(_ hub: inout SurfaceHub, _ outputs: [(Int, String)]) {
    for (number, name) in outputs {
        _ = hub.handle(.channel(bus: .output, channel: number, parameter: "stereo", value: .number(1)), now: 0)
        _ = hub.handle(.channel(bus: .output, channel: number, parameter: "name", value: .text(name)), now: 0)
    }
}

/// A driver that has started and been answered by the device, with the bytes of both steps;
/// `outputs` adds send targets after Phones.
private func connected(layout: LaunchControlModel, device: LaunchControlModel? = nil, outputs: [(Int, String)] = [],
                       sendOutputs: [Int?] = [])
    -> (driver: LaunchControlDriver, hub: SurfaceHub, midi: [UInt8]) {
    var hub = loadedHub()
    addOutputs(&hub, outputs)
    var driver = LaunchControlDriver(name: "lc", layout: layout, device: device, sendOutputs: sendOutputs)
    let start = driver.start(hub: &hub, now: 0)
    let answer = driver.receive([0x9F, 0x0C, 0x7F], hub: &hub, now: 0)
    return (driver, hub, start.midi + answer.midi)
}

final class LaunchControlDriverTests: XCTestCase {
    func testPositionsKeepTheMiddleExact() {
        XCTAssertEqual(LaunchControlDriver.position(64), 0.5)
        XCTAssertEqual(LaunchControlDriver.position(0), 0)
        XCTAssertEqual(LaunchControlDriver.position(127), 1)
        for value in UInt8(0)...127 {
            XCTAssertEqual(LaunchControlDriver.value(LaunchControlDriver.position(value)), value)
        }
    }

    func testStartAsksForDAWModeAndDrawsOnlyOnceAnswered() {
        var hub = loadedHub()
        var driver = LaunchControlDriver(name: "lc", layout: .xl3)
        let start = driver.start(hub: &hub, now: 0)
        XCTAssertEqual(Array(start.midi.prefix(6)), [0x9F, 0x0C, 0x00, 0x9F, 0x0C, 0x7F],
                       "leave DAW mode first, so the device answers even if a host left it in DAW mode")
        XCTAssertTrue(start.midi.contains([0xB6, 0x47, 0x7F]), "touch reports on")
        XCTAssertTrue(start.midi.contains([0xB6, 0x46, 0x7F]), "the device's fader pickup on")
        XCTAssertFalse(start.midi.contains([0xBF, 0x05]), "no positions before the device answers")
        XCTAssertEqual(hub.surfaceIDs.count, 4)
        XCTAssertFalse(driver.tick(hub: &hub, now: 1).midi.contains([0x9F, 0x0C, 0x7F]))
        XCTAssertTrue(driver.tick(hub: &hub, now: 3).midi.contains([0x9F, 0x0C, 0x7F]), "asked again after 3 s")

        let answer = driver.receive([0x9F, 0x0C, 0x7F], hub: &hub, now: 4)
        XCTAssertTrue(driver.isConnected)
        XCTAssertTrue(answer.midi.contains([0xB6, 0x1E, 0x01]), "DAW Mixer selected, for the Connect Only setting")
        XCTAssertTrue(answer.midi.contains([0xBF, 0x05, LaunchControlDriver.faderValue(0.5)]),
                      "fader 1 told its level, on the printed scale, for the device's pickup")
        XCTAssertTrue(answer.midi.contains([0xBF, 0x1D, 64]), "encoder 1 of the bottom row (pan) told the middle")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x1D, 5]), "Keys is red in TotalMix")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x1E, 3]), "Vox is white")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x21, 0]), "a blank strip's encoder is dark")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x0D, 45]),
                      "the top row sends to Phones, a white output that isn't in the control room: blue")
        XCTAssertTrue(answer.midi.contains(LaunchControlOutgoing.text(.stationary, field: 0, "In 1-3, PB 1") ?? []))
        XCTAssertTrue(answer.midi.contains(LaunchControlOutgoing.text(.control(.fader(0)), field: 0, "Keys") ?? []))
        XCTAssertTrue(answer.midi.contains(LaunchControlOutgoing.text(.control(.fader(0)), field: 1, "Level") ?? []))
        XCTAssertTrue(answer.midi.contains(LaunchControlOutgoing.text(.control(.encoder(row: 0, column: 0)), field: 1, "> Phones") ?? []))
        XCTAssertTrue(answer.midi.contains([0xB0, 0x25, 15]), "top buttons: PFL off, dark yellow")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x2D, LaunchControlDriver.muteOff]), "bottom buttons: mute off, dim orange")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x66, 0]), "Track >: no more strips with four sources")
    }

    func testXL3LayersBindFadersRowsAndButtons() {
        let (driver, hub, _) = connected(layout: .xl3)
        let keys = ChannelRef(.input, 0)
        XCTAssertEqual(hub.strips(of: driver.id(.faders))?[0].knobTarget, .level(keys, submix: 0))
        XCTAssertEqual(hub.strips(of: driver.id(.faders))?[0].switchTarget, .pfl(keys))
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 2), "top row: Phones")
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].switchTarget, .mute(keys))
        XCTAssertNil(hub.strips(of: driver.id(.row1))?[0].knobTarget, "middle row: no second send target")
        XCTAssertEqual(hub.strips(of: driver.id(.row2))?[0].knobTarget, .pan(keys, submix: 0), "bottom row: pan")
    }

    func testXL3ControlsReachTotalMix() {
        var (driver, hub, _) = connected(layout: .xl3)
        let sent = LaunchControlDriver.faderValue(0.5)
        let fader = driver.receive([0xBF, 0x05, sent], hub: &hub, now: 1)
        XCTAssertEqual(fader.core.messages,
                       [TotalMixCommand.setMix(from: .input, 0, to: 0, "faderlin", Float(LaunchControlDriver.faderPosition(sent)))],
                       "fader 1 at the level it was sent is caught")

        let pan = driver.receive([0xBF, 0x1D, 127], hub: &hub, now: 2)
        XCTAssertEqual(pan.core.messages.count, 1)
        XCTAssertTrue(pan.midi.contains(LaunchControlOutgoing.text(.control(.encoder(row: 2, column: 0)), field: 2, ValueText.pan(1)) ?? []))

        let pfl = driver.receive([0xB0, 0x25, 0x7F], hub: &hub, now: 3)
        XCTAssertEqual(pfl.core.messages, [TotalMixCommand.set(.input, 0, "pfl", 1)])
        XCTAssertTrue(pfl.midi.contains([0xB0, 0x25, 13]), "PFL on: yellow")
        XCTAssertEqual(driver.receive([0xB0, 0x25, 0x00], hub: &hub, now: 3.1).core.messages, [], "a release does nothing")

        let mute = driver.receive([0xB0, 0x2D, 0x7F], hub: &hub, now: 4)
        XCTAssertEqual(mute.core.messages, [TotalMixCommand.set(.input, 0, "mute", 1)])
        XCTAssertTrue(mute.midi.contains([0xB0, 0x2D, LaunchControlDriver.muteOn]), "mute on: orange")
    }

    func testFaderAwayFromItsLevelIsHeldBack() {
        var (driver, hub, _) = connected(layout: .xl3)
        XCTAssertEqual(driver.receive([0xBF, 0x05, 10], hub: &hub, now: 1).core.messages, [],
                       "the hub's pickup holds a fader the device didn't hold")
    }

    func testPageAndShiftPageChooseEachSendRowSkippingTheOther() {
        var (driver, hub, _) = connected(layout: .xl3, outputs: [(4, "ADAT 1/2"), (6, "ADAT 3/4")])
        let keys = ChannelRef(.input, 0)
        XCTAssertEqual(hub.sendTargets, [2, 4, 6])
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 2), "top: Phones")
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].knobTarget, .level(keys, submix: 4), "middle: ADAT 1/2")
        let down = driver.receive([0xB0, 0x6B, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 6),
                       "Page down: the top row skips the middle row's ADAT 1/2")
        XCTAssertTrue(down.midi.contains(LaunchControlOutgoing.text(.overlay, field: 0, "Top row") ?? []))
        XCTAssertTrue(down.midi.contains(LaunchControlOutgoing.text(.overlay, field: 1, "> ADAT 3/4") ?? []))
        XCTAssertTrue(down.midi.contains([0xB0, 0x6B, 0]), "Page down dark: nothing further for the top row")
        XCTAssertEqual(driver.sendOutputs, [6, 4], "the middle row keeps ADAT 1/2")
        _ = driver.receive([0xB6, 0x3F, 0x7F], hub: &hub, now: 2)
        let shiftUp = driver.receive([0xB0, 0x6A, 0x7F], hub: &hub, now: 2)
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].knobTarget, .level(keys, submix: 2), "Shift + Page up: the middle row to Phones")
        XCTAssertTrue(shiftUp.midi.contains(LaunchControlOutgoing.text(.overlay, field: 0, "Middle row") ?? []))
        XCTAssertEqual(driver.sendOutputs, [6, 2])
        XCTAssertTrue(driver.receive([0xB0, 0x6A, 0x7F], hub: &hub, now: 3).midi.isEmpty, "nothing before Phones")
        _ = driver.receive([0xB6, 0x3F, 0x00], hub: &hub, now: 4)
        let up = driver.receive([0xB0, 0x6A, 0x7F], hub: &hub, now: 4)
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 4), "Page up: ADAT 1/2, now free")
        XCTAssertFalse(up.midi.isEmpty)
    }

    func testSavedSendRowsAreUsedAndGiveWayWhenTheirOutputIsGone() {
        let keys = ChannelRef(.input, 0)
        var (driver, hub, _) = connected(layout: .xl3, outputs: [(4, "ADAT 1/2"), (6, "ADAT 3/4")], sendOutputs: [6, 4])
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 6))
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].knobTarget, .level(keys, submix: 4))
        let home = hub.setHomeSubmix(6, now: 1)  // ADAT 3/4 stops being a send target
        _ = driver.take(home, hub: &hub, now: 1)
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget?.channel, keys)
        XCTAssertNotEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 4), "never the middle row's")
        XCTAssertEqual(driver.sendOutputs, [6, 4], "the choice is kept for when ADAT 3/4 comes back")
    }

    func testLaunchControl3Layout() {
        var (driver, hub, midi) = connected(layout: .lc3)
        let keys = ChannelRef(.input, 0)
        XCTAssertEqual(driver.layers, [.row1, .row0])
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].knobTarget, .level(keys, submix: 0), "bottom row: level")
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].switchTarget, .mute(keys), "buttons: mute")
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .pan(keys, submix: 0), "top row: pan")
        XCTAssertTrue(midi.contains([0xF0, 0x00, 0x20, 0x29, 0x02, 0x16]), "the Launch Control 3's header")
        XCTAssertFalse(midi.contains([0xB6, 0x46]), "no fader pickup on a device without faders")
        XCTAssertTrue(midi.contains([0xB0, 0x42, LaunchControlDriver.functionIdle]))

        let track = driver.receive([0xB0, 0x6B, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 2), "Page ▼: send 1")
        XCTAssertTrue(track.midi.contains(LaunchControlOutgoing.text(.overlay, field: 1, "> Phones", model: .lc3) ?? []))
        XCTAssertTrue(driver.receive([0xB0, 0x6B, 0x7F], hub: &hub, now: 2).midi.isEmpty, "no second send")
        _ = driver.receive([0xB0, 0x6A, 0x7F], hub: &hub, now: 3)
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .pan(keys, submix: 0), "Page ▲: back to pan")

        let function = driver.receive([0xB0, 0x42, 0x7F], hub: &hub, now: 4)
        XCTAssertTrue(driver.buttonsArePFL)
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].switchTarget, .pfl(keys))
        XCTAssertTrue(function.midi.contains([0xB0, 0x42, LaunchControlDriver.pflOn]), "Function lit yellow")
        XCTAssertTrue(function.midi.contains([0xB0, 0x25, LaunchControlDriver.pflOff]), "buttons dark yellow")
        XCTAssertEqual(driver.receive([0xB0, 0x25, 0x7F], hub: &hub, now: 5).core.messages,
                       [TotalMixCommand.set(.input, 0, "pfl", 1)])
        let release = driver.receive([0xB0, 0x42, 0x00], hub: &hub, now: 5.5)
        XCTAssertFalse(driver.buttonsArePFL, "PFL only while Function is held")
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].switchTarget, .mute(keys))
        XCTAssertTrue(release.midi.contains([0xB0, 0x42, LaunchControlDriver.functionIdle]))
        let level = driver.receive([0xBF, 0x15, 127], hub: &hub, now: 6)
        XCTAssertEqual(level.core.messages.count, 1, "the bottom row's encoders follow, with no pickup")
    }

    func testLaunchControl3LayoutOnAnXL3() {
        var (driver, hub, midi) = connected(layout: .lc3, device: .xl3)
        XCTAssertTrue(midi.contains([0xF0, 0x00, 0x20, 0x29, 0x02, 0x15]), "the XL 3's header")
        XCTAssertTrue(midi.contains([0xB6, 0x46, 0x00]), "the XL 3's fader pickup off")
        XCTAssertTrue(midi.contains([0xB0, 0x1D, 0]), "the bottom encoder row is dark")
        XCTAssertTrue(midi.contains([0xB0, 0x2D, 0]), "the bottom button row is dark")
        XCTAssertTrue(midi.contains([0xB0, 0x76, 0]), "Record is dark")
        XCTAssertEqual(driver.receive([0xBF, 0x05, 64], hub: &hub, now: 1).core.messages, [], "faders do nothing")
        XCTAssertEqual(driver.receive([0xB0, 0x2D, 0x7F], hub: &hub, now: 1).core.messages, [], "bottom buttons do nothing")
        _ = driver.receive([0xB0, 0x41, 0x7F], hub: &hub, now: 2)
        XCTAssertFalse(driver.buttonsArePFL, "Solo/Arm does nothing")
        _ = driver.receive([0xB0, 0x42, 0x7F], hub: &hub, now: 2)
        XCTAssertTrue(driver.buttonsArePFL, "Mute/Select is Function (66)")
        _ = driver.receive([0xB0, 0x42, 0x00], hub: &hub, now: 3)
        XCTAssertFalse(driver.buttonsArePFL)
    }

    func testACustomModeStopsDrawingAndDAWMixerDrawsAgain() {
        var (driver, hub, _) = connected(layout: .xl3)
        _ = driver.receive([0xB6, 0x1E, 0x06], hub: &hub, now: 1)
        let change = hub.handle(.mix(bus: .input, channel: 0, output: 0, parameter: "faderlin", value: .number(0.25)), now: 2)
        XCTAssertTrue(driver.take(change, hub: &hub, now: 2).midi.isEmpty, "nothing drawn in a Custom Mode")
        let back = driver.receive([0xB6, 0x1E, 0x01], hub: &hub, now: 3)
        XCTAssertTrue(back.midi.contains([0xBF, 0x05, LaunchControlDriver.faderValue(0.25)]), "everything sent again")
    }

    func testStopLeavesDAWModeAndTheHub() {
        var (driver, hub, _) = connected(layout: .xl3)
        XCTAssertEqual(driver.stop(hub: &hub), [0x9F, 0x0C, 0x00])
        XCTAssertTrue(hub.surfaceIDs.isEmpty)
    }

    func testColorsAndNames() {
        let source = StripInfo(channel: ChannelRef(.input, 0), name: "Keys", color: 6, stereo: true, kind: .source,
                               knobLabel: "", switchLabel: "")
        XCTAssertEqual(LaunchControlDriver.color(for: source), 21)
        var output = source
        output.kind = .monitoring
        output.color = 1
        XCTAssertEqual(LaunchControlDriver.color(for: output), 21, "a white monitoring output shows green")
        output.kind = .send
        XCTAssertEqual(LaunchControlDriver.color(for: output), 45, "a white send shows blue")
        XCTAssertEqual(LaunchControlDriver.color(for: nil), 0)
    }

    func testLevelAndSendEncodersUseTheARCScale() {
        // The ARC USB's detents, as TotalMix showed them (docs/TOTALMIX-OSC.md, test 19).
        XCTAssertNil(LaunchControlDriver.encoderGain(exactly: 0), "value 0 is off")
        XCTAssertEqual(LaunchControlDriver.encoderGain(exactly: 1), -63.5)
        XCTAssertEqual(LaunchControlDriver.encoderGain(exactly: 101), 0, "0 dB at 101, as on the faders")
        XCTAssertEqual(LaunchControlDriver.encoderGain(exactly: 127), 6)
        XCTAssertEqual(LaunchControlDriver.encoderValue(FaderCurve.unityPosition), 101)
        XCTAssertEqual(LaunchControlDriver.encoderValue(0), 0)
        XCTAssertEqual(LaunchControlDriver.encoderValue(1), 127)
        // Steps: about 0.2 dB a value near 0 dB, and no more than 1.27 dB anywhere.
        var previous = LaunchControlDriver.encoderGain(exactly: 1) ?? 0
        for value in 2...127 {
            let gain = LaunchControlDriver.encoderGain(exactly: Double(value)) ?? 0
            XCTAssertGreaterThan(gain, previous)
            XCTAssertLessThanOrEqual(gain - previous, 1.27, "value \(value)")
            previous = gain
        }
        let nearUnity = (LaunchControlDriver.encoderGain(exactly: 102) ?? 0) - (LaunchControlDriver.encoderGain(exactly: 101) ?? 0)
        XCTAssertEqual(nearUnity, 0.21, accuracy: 0.01)
        // Every value comes back from its own position.
        for value in UInt8(0)...127 {
            XCTAssertEqual(LaunchControlDriver.encoderValue(LaunchControlDriver.encoderPosition(value)), value)
        }

        var (driver, hub, _) = connected(layout: .lc3, device: .xl3)
        let level = driver.receive([0xBF, 0x15, 101], hub: &hub, now: 1)
        XCTAssertEqual(level.core.messages,
                       [TotalMixCommand.setMix(from: .input, 0, to: 0, "faderlin", Float(FaderCurve.position(gainDB: 0)))],
                       "the Launch Control 3's level row at 101 is 0 dB")
    }

    func testPanEncodersLandOnTotalMixsWholeSteps() {
        XCTAssertEqual(LaunchControlDriver.panSteps(64), 0)
        XCTAssertEqual(LaunchControlDriver.panSteps(0), -100)
        XCTAssertEqual(LaunchControlDriver.panSteps(127), 100)
        XCTAssertEqual(LaunchControlDriver.panPosition(64), 0.5)
        XCTAssertEqual(LaunchControlDriver.panPosition(127), 1)
        XCTAssertEqual(LaunchControlDriver.panPosition(0), 0)
        for value in UInt8(0)...127 {
            let steps = LaunchControlDriver.panSteps(value)
            let pan = LaunchControlDriver.panPosition(value) * 2 - 1
            XCTAssertEqual(ValueText.pan(pan), steps == 0 ? "C" : steps < 0 ? "L\(-steps)" : "R\(steps)",
                           "the display shows the whole step sent, at \(value)")
            XCTAssertEqual(Int((pan * 100).rounded(.down)), steps, "TotalMix's step (the one below) is the same, at \(value)")
            XCTAssertEqual(LaunchControlDriver.panValue(LaunchControlDriver.panPosition(value)), value)
            if value > 0 {
                let gap = steps - LaunchControlDriver.panSteps(value - 1)
                XCTAssertTrue(gap == 1 || gap == 2, "steps of 1 or 2, at \(value)")
            }
        }
        XCTAssertEqual(LaunchControlDriver.panValue(0.5 + 0.01 / 2), 65, "R1 from TotalMix: the nearest value")

        var (driver, hub, _) = connected(layout: .xl3)
        let right = driver.receive([0xBF, 0x1D, 65], hub: &hub, now: 1)
        XCTAssertEqual(right.core.messages, [TotalMixCommand.setMix(from: .input, 0, to: 0, "balpan", Float(0.0225))])
        XCTAssertTrue(right.midi.contains(LaunchControlOutgoing.text(.control(.encoder(row: 2, column: 0)), field: 2, "R2") ?? []))
    }

    func testTheHomeScreenTitleCountsEachKind() {
        let order = [ChannelRef(.input, 0), ChannelRef(.input, 2), ChannelRef(.input, 3),
                     ChannelRef(.playback, 0), ChannelRef(.playback, 2)]
        XCTAssertEqual(LaunchControlDriver.pageTitle(Array(order[0...2]), order: order), "Inputs 1-3")
        XCTAssertEqual(LaunchControlDriver.pageTitle(Array(order[3...4]), order: order), "Playbacks 1-2")
        XCTAssertEqual(LaunchControlDriver.pageTitle([order[4]], order: order), "Playback 2")
        XCTAssertEqual(LaunchControlDriver.pageTitle(Array(order[1...3]), order: order), "In 2-3, PB 1")
        XCTAssertEqual(LaunchControlDriver.pageTitle([], order: order), "No channels")

        var hub = loadedHub()
        var layout = hub.layout
        layout.playbacksOnNewPage = true  // inputs 1-3, five blanks, then the playback
        _ = hub.setLayout(layout, now: 0)
        var driver = LaunchControlDriver(name: "lc", layout: .xl3)
        _ = driver.start(hub: &hub, now: 0)
        _ = driver.receive([0x9F, 0x0C, 0x7F], hub: &hub, now: 0)
        XCTAssertEqual(driver.stationaryLines(hub: hub)[0], "Inputs 1-3")
        let track = driver.receive([0xB0, 0x66, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(driver.stationaryLines(hub: hub)[0], "Playback 1", "not 'Channels 9-9'")
        XCTAssertTrue(track.midi.contains(LaunchControlOutgoing.text(.stationary, field: 0, "Playback 1") ?? []))
        XCTAssertTrue(track.midi.contains(LaunchControlOutgoing.showDisplay(.stationary, true, model: .xl3) ?? []),
                      "the home screen brought up again with its new title")
    }

    func testARowWhoseOutputIsGoneDoesNotTakeTheOtherRowsChoice() {
        // Review of 2026-11-02: rows [6, 2], then output 6 becomes the cue output.
        var (driver, hub, _) = connected(layout: .xl3, outputs: [(4, "ADAT 1/2"), (6, "ADAT 3/4")], sendOutputs: [6, 2])
        XCTAssertEqual(driver.currentSendOutputs(hub: hub), [6, 2])
        let cue = hub.handle(.other(path: "controlroom/cuechan", value: .number(6)), now: 1)
        _ = driver.take(cue, hub: &hub, now: 1)
        XCTAssertEqual(driver.currentSendOutputs(hub: hub), [4, 2], "the middle row keeps Phones; the top row takes what's free")
        XCTAssertEqual(driver.sendOutputs, [6, 2], "the saved choices stay, for when output 6 comes back")
    }

    func testLeavingDAWModeDoesNotLookLikeAnAnswer() {
        var hub = loadedHub()
        var driver = LaunchControlDriver(name: "lc", layout: .xl3)
        _ = driver.start(hub: &hub, now: 0)
        // The device's replies when a host leaves DAW mode, then its echo of the new request.
        let leaving = driver.receive([0xB6, 0x1E, 0x06, 0xB6, 0x1F, 0x06, 0x9F, 0x0C, 0x00], hub: &hub, now: 0.01)
        XCTAssertFalse(driver.isConnected)
        XCTAssertTrue(leaving.midi.isEmpty, "nothing drawn on a device on its way out")
        let entering = driver.receive([0x9F, 0x0C, 0x7F], hub: &hub, now: 0.02)
        XCTAssertTrue(driver.isConnected)
        XCTAssertTrue(entering.midi.contains(LaunchControlOutgoing.text(.stationary, field: 0, "In 1-3, PB 1") ?? []), "one full draw")
    }

    func testAnOutputsNewColorReachesItsSendRow() {
        var (driver, hub, midi) = connected(layout: .xl3)
        XCTAssertTrue(midi.contains([0xB0, 0x0D, 45]), "Phones, white in TotalMix, is blue")
        let recolor = hub.handle(.channel(bus: .output, channel: 2, parameter: "color", value: .number(4)), now: 1)
        let step = driver.take(recolor, hub: &hub, now: 1)
        XCTAssertTrue(step.midi.contains([0xB0, 0x0D, 5]), "TotalMix's red reaches the top row at once")
    }

    func testTheAppCanSetASendRow() {
        var (driver, hub, _) = connected(layout: .xl3, outputs: [(4, "ADAT 1/2"), (6, "ADAT 3/4")])
        XCTAssertEqual(driver.currentSendOutputs(hub: hub), [2, 4])
        let step = driver.setSendOutput(row: 1, to: 6, hub: &hub, now: 1)
        XCTAssertEqual(driver.currentSendOutputs(hub: hub), [2, 6])
        XCTAssertEqual(driver.sendOutputs, [2, 6], "the top row kept its output")
        XCTAssertTrue(step.midi.contains(LaunchControlOutgoing.text(.overlay, field: 1, "> ADAT 3/4") ?? []))
        XCTAssertTrue(step.midi.contains(LaunchControlOutgoing.text(.stationary, field: 2, "Mid > ADAT 3/4") ?? []))
        XCTAssertTrue(driver.setSendOutput(row: 0, to: 6, hub: &hub, now: 2).midi.isEmpty, "the other row's output is refused")
        XCTAssertTrue(driver.setSendOutput(row: 0, to: nil, hub: &hub, now: 2).midi.isEmpty, "no pan on the XL 3")
        XCTAssertTrue(driver.setSendOutput(row: 0, to: 99, hub: &hub, now: 2).midi.isEmpty, "not a send target")

        var (lc3, lc3Hub, _) = connected(layout: .lc3)
        _ = lc3.setSendOutput(row: 0, to: 2, hub: &lc3Hub, now: 1)
        XCTAssertEqual(lc3.currentSendOutputs(hub: lc3Hub), [2])
        _ = lc3.setSendOutput(row: 0, to: nil, hub: &lc3Hub, now: 2)
        XCTAssertEqual(lc3.currentSendOutputs(hub: lc3Hub), [nil], "back to pan")
    }

    func testTheHomeScreenShowsWhereTheRowsGo() {
        var (driver, hub, midi) = connected(layout: .xl3, outputs: [(4, "ADAT 1/2"), (6, "ADAT 3/4")])
        XCTAssertEqual(driver.stationaryLines(hub: hub), ["In 1-3, PB 1", "Top > Phones", "Mid > ADAT 1/2"])
        XCTAssertTrue(midi.contains(LaunchControlOutgoing.text(.stationary, field: 1, "Top > Phones") ?? []))
        _ = driver.receive([0xB6, 0x3F, 0x7F], hub: &hub, now: 1)
        let shiftPage = driver.receive([0xB0, 0x6B, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(driver.stationaryLines(hub: hub)[2], "Mid > ADAT 3/4")
        XCTAssertTrue(shiftPage.midi.contains(LaunchControlOutgoing.text(.stationary, field: 2, "Mid > ADAT 3/4") ?? []),
                      "the home screen follows the row")

        var (lc3, lc3Hub, _) = connected(layout: .lc3)
        XCTAssertEqual(lc3.stationaryLines(hub: lc3Hub), ["In 1-3, PB 1", "Top: Pan", "Buttons: Mute"])
        _ = lc3.receive([0xB0, 0x6B, 0x7F], hub: &lc3Hub, now: 1)
        let function = lc3.receive([0xB0, 0x42, 0x7F], hub: &lc3Hub, now: 2)
        XCTAssertEqual(lc3.stationaryLines(hub: lc3Hub), ["In 1-3, PB 1", "Top > Phones", "Buttons: PFL"])
        XCTAssertTrue(function.midi.contains(LaunchControlOutgoing.text(.stationary, field: 2, "Buttons: PFL", model: .lc3) ?? []))
    }

    func testShiftAndTurnResetsAnEncoder() {
        var (driver, hub, _) = connected(layout: .xl3)
        _ = driver.receive([0xBF, 0x1D, 127], hub: &hub, now: 1)  // pan right
        _ = driver.receive([0xBF, 0x0D, 100], hub: &hub, now: 1)  // send up
        let sendBefore = hub.mirror.value(of: .level(ChannelRef(.input, 0), submix: 2))
        XCTAssertEqual(driver.receive([0xBE, 0x1D, 0x7F], hub: &hub, now: 2).core.messages, [],
                       "a turn without Shift resets nothing")
        _ = driver.receive([0xBE, 0x1D, 0x00], hub: &hub, now: 2)

        _ = driver.receive([0xB6, 0x3F, 0x7F], hub: &hub, now: 3)
        XCTAssertEqual(driver.receive([0xBE, 0x1D, 0x7F], hub: &hub, now: 3.1).core.messages, [],
                       "not before Shift has been held 0.3 s")
        let pan = driver.receive([0xBE, 0x1D, 0x7F], hub: &hub, now: 3.4)
        XCTAssertEqual(pan.core.messages, [TotalMixCommand.setMix(from: .input, 0, to: 0, "balpan", 0)], "pan to the center")
        XCTAssertTrue(pan.midi.contains([0xBF, 0x1D, 64]), "the encoder told the center, to carry on from there")
        let send = driver.receive([0xBE, 0x0D, 0x7F], hub: &hub, now: 3.4)
        XCTAssertEqual(send.core.messages, [TotalMixCommand.setMix(from: .input, 0, to: 2, "faderlin", 0)], "a send to -oo")
        XCTAssertTrue(send.midi.contains([0xBF, 0x0D, 0]))
        XCTAssertEqual(driver.receive([0xBE, 0x0D, 0x7F], hub: &hub, now: 3.6).core.messages, [],
                       "one reset per encoder per hold of Shift, however many touch reports a turn sends")
        XCTAssertEqual(driver.receive([0xBE, 0x05, 0x7F], hub: &hub, now: 3.6).core.messages, [],
                       "a fader moved with Shift held isn't reset")
        _ = driver.receive([0xB6, 0x3F, 0x00], hub: &hub, now: 4)

        // A second Shift + turn brings the send back.
        _ = driver.receive([0xB6, 0x3F, 0x7F], hub: &hub, now: 5)
        let restore = driver.receive([0xBE, 0x0D, 0x7F], hub: &hub, now: 5.4)
        XCTAssertEqual(restore.core.messages.count, 1)
        XCTAssertEqual(Double(hub.mirror.value(of: .level(ChannelRef(.input, 0), submix: 2)) ?? -1), sendBefore ?? -2,
                       accuracy: 0.0001, "the send is back where it was")
        _ = driver.receive([0xB6, 0x3F, 0x00], hub: &hub, now: 6)

        // Shift held for Shift + Page: a brushed encoder changes nothing.
        _ = driver.receive([0xB6, 0x3F, 0x7F], hub: &hub, now: 7)
        _ = driver.receive([0xB0, 0x6B, 0x7F], hub: &hub, now: 7.1)
        XCTAssertEqual(driver.receive([0xBE, 0x1D, 0x7F], hub: &hub, now: 7.5).core.messages, [],
                       "no reset once Page or Track has been pressed in this hold of Shift")
    }

    func testShiftAndTurnNeverRaisesALevel() {
        var (lc3, hub, _) = connected(layout: .lc3, device: .xl3)
        _ = lc3.receive([0xB6, 0x3F, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(lc3.receive([0xBE, 0x15, 0x7F], hub: &hub, now: 1.5).core.messages, [],
                       "a level below 0 dB stays where it is")
        _ = lc3.receive([0xB6, 0x3F, 0x00], hub: &hub, now: 2)
        _ = lc3.receive([0xBF, 0x15, 127], hub: &hub, now: 3)  // +6 dB
        _ = lc3.receive([0xB6, 0x3F, 0x7F], hub: &hub, now: 4)
        let level = lc3.receive([0xBE, 0x15, 0x7F], hub: &hub, now: 4.5)
        XCTAssertEqual(level.core.messages,
                       [TotalMixCommand.setMix(from: .input, 0, to: 0, "faderlin", Float(FaderCurve.position(gainDB: 0)))],
                       "a level above 0 dB comes down to 0 dB")
    }

    // From the review of 2026-11-01.

    func testAPositionEqualToTheLastSentIsSentAgainAfterTheDeviceMoved() {
        var (driver, hub, _) = connected(layout: .xl3)
        _ = driver.receive([0xBF, 0x1D, 40], hub: &hub, now: 1)
        _ = driver.take(hub.tick(now: 2), hub: &hub, now: 2)
        let back = hub.handle(.mix(bus: .input, channel: 0, output: 0, parameter: "balpan", value: .number(0)), now: 3)
        XCTAssertTrue(driver.take(back, hub: &hub, now: 3).midi.contains([0xBF, 0x1D, 64]),
                      "the encoder is told the pan is centered again")
    }

    func testThePositionIsSentAfterPaging() {
        var hub = loadedHub()
        var layout = hub.layout
        layout.playbacksOnNewPage = true
        _ = hub.setLayout(layout, now: 0)
        var driver = LaunchControlDriver(name: "lc", layout: .xl3)
        _ = driver.start(hub: &hub, now: 0)
        _ = driver.receive([0x9F, 0x0C, 0x7F], hub: &hub, now: 0)
        _ = driver.receive([0xBF, 0x1D, 40], hub: &hub, now: 1)
        _ = driver.take(hub.tick(now: 2), hub: &hub, now: 2)
        XCTAssertTrue(driver.receive([0xB0, 0x66, 0x7F], hub: &hub, now: 3).midi.contains([0xBF, 0x1D, 64]),
                      "Track >: the playback's centered pan is sent, though 64 was sent before")
    }

    func testLeavingDAWModeIsAskedAgain() {
        var (driver, hub, _) = connected(layout: .xl3)
        _ = driver.receive([0x9F, 0x0C, 0x00], hub: &hub, now: 1)
        XCTAssertFalse(driver.isConnected)
        XCTAssertTrue(driver.tick(hub: &hub, now: 4).midi.contains([0x9F, 0x0C, 0x7F]))
    }

    func testAFastFirstFaderMoveIsTaken() {
        var (driver, hub, _) = connected(layout: .xl3)
        let first = driver.receive([0xBF, 0x05, 72], hub: &hub, now: 1)
        XCTAssertEqual(first.core.messages.count, 1, "11 values past the level, let through by the device")
    }

    func testPageLightsFollowTheSendTargets() {
        var (driver, hub, _) = connected(layout: .lc3)
        XCTAssertTrue(driver.receive([0xB0, 0x6B, 0x7F], hub: &hub, now: 1).midi.contains([0xB0, 0x6B, 0]),
                      "Track > dark at the last send")
        var output = CoreOutput()
        for event in [TotalMixEvent.channel(bus: .output, channel: 4, parameter: "stereo", value: .number(1)),
                      .channel(bus: .output, channel: 4, parameter: "name", value: .text("Phones 2"))] {
            output.append(hub.handle(event, now: 2))
        }
        XCTAssertTrue(driver.take(output, hub: &hub, now: 2).midi.contains([0xB0, 0x6B, LaunchControlDriver.navigationOn]))
    }

    func testTheLaunchControl3TopRowGoesBackToPanWhenItsSendIsGone() {
        var (driver, hub, _) = connected(layout: .lc3)
        let keys = ChannelRef(.input, 0)
        _ = driver.receive([0xB0, 0x6B, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(driver.sendOutputs, [2])
        _ = driver.take(hub.setHomeSubmix(2, now: 2), hub: &hub, now: 2)
        XCTAssertEqual(hub.sendTargets, [0])
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .pan(keys, submix: 2), "Phones is the mix now: pan")
        _ = driver.take(hub.setHomeSubmix(nil, now: 3), hub: &hub, now: 3)
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 2), "and back to the Phones send")
    }

    func testTheFaderScaleMatchesTheTicks() {
        for tick in LaunchControlDriver.faderTicks {
            let position = LaunchControlDriver.faderPosition(exactly: tick.value)
            XCTAssertEqual(FaderCurve.gainDB(position: position) ?? -999, tick.gainDB, accuracy: 0.01, "tick \(tick.value)")
        }
        XCTAssertNil(FaderCurve.gainDB(position: LaunchControlDriver.faderPosition(0)), "the bottom is off")
        XCTAssertEqual(LaunchControlDriver.faderPosition(127), 1, accuracy: 1e-9)
        var previous = -1.0
        for value in UInt8(0)...127 {
            let position = LaunchControlDriver.faderPosition(value)
            XCTAssertGreaterThan(position, previous, "rising at \(value)")
            previous = position
            XCTAssertEqual(LaunchControlDriver.faderValue(position), value, "round trip at \(value)")
        }
        XCTAssertEqual(LaunchControlDriver.faderValue(FaderCurve.unityPosition), 101, "0 dB sits on the third tick")
    }

    func testFadersUseTheScaleAndEncodersDoNot() {
        var (driver, hub, midi) = connected(layout: .xl3)
        XCTAssertTrue(midi.contains([0xBF, 0x05, LaunchControlDriver.faderValue(0.5)]), "fader 1 told its level on the scale")
        XCTAssertTrue(midi.contains([0xBF, 0x0D, LaunchControlDriver.encoderValue(0.5)]), "send encoders use the ARC scale")
        XCTAssertTrue(midi.contains([0xBF, 0x1D, 64]), "pan encoders keep the plain scale, centered at 64")
        let unity = driver.receive([0xBF, 0x05, LaunchControlDriver.faderValue(0.5)], hub: &hub, now: 1)
        XCTAssertEqual(unity.core.messages.count, 1)
        let top = driver.receive([0xBF, 0x05, 101], hub: &hub, now: 2)
        XCTAssertEqual(top.core.messages, [TotalMixCommand.setMix(from: .input, 0, to: 0, "faderlin", Float(FaderCurve.unityPosition))])
    }

    func testTrackMovesTheStripsByEightOrWithShiftToTheEnds() {
        var hub = loadedHub()
        var layout = hub.layout
        layout.playbacksOnNewPage = true  // inputs 1-3, five blanks, then the playback: two pages
        _ = hub.setLayout(layout, now: 0)
        var driver = LaunchControlDriver(name: "lc", layout: .xl3)
        _ = driver.start(hub: &hub, now: 0)
        _ = driver.receive([0x9F, 0x0C, 0x7F], hub: &hub, now: 0)
        _ = driver.receive([0xB0, 0x66, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(hub.strips(of: driver.id(.faders))?[0].knobTarget, .level(ChannelRef(.playback, 0), submix: 0),
                       "Track >: the next eight")
        XCTAssertEqual(hub.strips(of: driver.id(.row2))?[0].knobTarget, .pan(ChannelRef(.playback, 0), submix: 0),
                       "every layer moves together")
        _ = driver.receive([0xB6, 0x3F, 0x7F], hub: &hub, now: 2)
        _ = driver.receive([0xB0, 0x67, 0x7F], hub: &hub, now: 2)
        XCTAssertEqual(hub.strips(of: driver.id(.faders))?[0].knobTarget, .level(ChannelRef(.input, 0), submix: 0),
                       "Shift + Track <: the first page")
        _ = driver.receive([0xB0, 0x66, 0x7F], hub: &hub, now: 3)
        XCTAssertEqual(hub.strips(of: driver.id(.faders))?[0].knobTarget, .level(ChannelRef(.playback, 0), submix: 0),
                       "Shift + Track >: the last page, starting on a multiple of eight")
    }


    func testSendRowsResolveAndSetWithoutADriver() {
        let targets = [2, 4, 6]
        var xl3 = LaunchControlSendRows(layout: .xl3)
        XCTAssertEqual(xl3.choices, [nil, nil])
        XCTAssertEqual(xl3.outputs(targets: targets), [2, 4], "each row takes the first output free")
        XCTAssertEqual(xl3.available(row: 0, targets: targets), [2, 6])
        XCTAssertFalse(xl3.set(row: 0, to: 4, targets: targets), "the other row's output")
        XCTAssertFalse(xl3.set(row: 0, to: nil, targets: targets), "no pan on the XL 3")
        XCTAssertFalse(xl3.set(row: 0, to: 8, targets: targets), "not a send target")
        XCTAssertTrue(xl3.set(row: 0, to: 6, targets: targets))
        XCTAssertEqual(xl3.choices, [6, 4], "the other row is pinned to what it fed")
        XCTAssertEqual(xl3.outputs(targets: [2, 6]), [6, 2], "an output gone: the row takes a free one")
        XCTAssertEqual(xl3.choices, [6, 4], "and its choice is kept for when it returns")

        var lc3 = LaunchControlSendRows(layout: .lc3, choices: [4, 6])
        XCTAssertEqual(lc3.choices, [4], "one row")
        XCTAssertEqual(lc3.outputs(targets: [2, 6]), [nil], "pan while its output is gone")
        XCTAssertTrue(lc3.set(row: 0, to: nil, targets: targets))
        XCTAssertEqual(lc3.outputs(targets: targets), [nil])
    }

    func testAPresenceCheckNoticesADeviceThatLostDAWMode() {
        var (driver, hub, _) = connected(layout: .xl3)
        let query = LaunchControlOutgoing.queryFeature(0x1E)
        XCTAssertTrue(driver.tick(hub: &hub, now: 4.9).midi.isEmpty, "quiet for under 5 s: nothing")
        XCTAssertEqual(driver.tick(hub: &hub, now: 5).midi, query, "asks for the surface mode")
        XCTAssertTrue(driver.tick(hub: &hub, now: 6).midi.isEmpty, "once per 5 s")
        _ = driver.receive([0xB6, 0x1E, 0x01], hub: &hub, now: 5.01)   // the answer: a DAW mode
        XCTAssertTrue(driver.isConnected)
        XCTAssertTrue(driver.tick(hub: &hub, now: 9).midi.isEmpty)

        // An answer of a Custom Mode the device never announced: it restarted (inference).
        XCTAssertEqual(driver.tick(hub: &hub, now: 10.01).midi, query)
        let restart = driver.receive([0xB6, 0x1E, 0x06], hub: &hub, now: 10.02)
        XCTAssertFalse(driver.isConnected)
        XCTAssertTrue(restart.midi.contains(LaunchControlOutgoing.dawMode(true)), "asks for DAW mode again")
        _ = driver.receive([0x9F, 0x0C, 0x7F], hub: &hub, now: 10.1)
        XCTAssertTrue(driver.isConnected)

        // A Custom Mode chosen on the device is announced, and is left alone.
        _ = driver.receive([0xB6, 0x1E, 0x06], hub: &hub, now: 11)
        XCTAssertTrue(driver.isConnected)
        XCTAssertEqual(driver.tick(hub: &hub, now: 16).midi, query)
        XCTAssertTrue(driver.receive([0xB6, 0x1E, 0x06], hub: &hub, now: 16.01).midi.isEmpty,
                      "the answer agrees with what it announced")

        // Silence through two questions: asks for DAW mode again.
        XCTAssertEqual(driver.tick(hub: &hub, now: 21.02).midi, query)
        XCTAssertTrue(driver.tick(hub: &hub, now: 27.02).midi.contains(LaunchControlOutgoing.dawMode(true)))
        XCTAssertFalse(driver.isConnected)
    }

    func testTheNovationButtonGoesToTheFirstPage() {
        var (driver, hub, _) = connected(layout: .xl3, outputs: [(2, "Phones")])
        for channel in 0..<20 {
            _ = hub.handle(.channel(bus: .input, channel: channel, parameter: "name", value: .text("In \(channel + 1)")), now: 0)
        }
        _ = driver.receive([0xB0, 0x66, 0x7F], hub: &hub, now: 1)   // Track >
        guard case .strips(_, let moved, _, _)? = hub.mode(of: driver.id(.faders)) else { return XCTFail() }
        XCTAssertEqual(moved, 8)
        _ = driver.receive([0xB0, 0x68, 0x7F], hub: &hub, now: 2)   // the Novation button
        guard case .strips(_, let first, _, _)? = hub.mode(of: driver.id(.faders)) else { return XCTFail() }
        XCTAssertEqual(first, 0)
        guard case .strips(_, let row0, _, _)? = hub.mode(of: driver.id(.row0)) else { return XCTFail() }
        XCTAssertEqual(row0, 0, "every layer moves")
    }
}
