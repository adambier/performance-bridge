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

/// A driver that has started and been answered by the device, with the bytes of both steps.
private func connected(layout: LaunchControlModel, device: LaunchControlModel? = nil)
    -> (driver: LaunchControlDriver, hub: SurfaceHub, midi: [UInt8]) {
    var hub = loadedHub()
    var driver = LaunchControlDriver(name: "lc", layout: layout, device: device)
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
        XCTAssertTrue(start.midi.contains([0x9F, 0x0C, 0x7F]))
        XCTAssertTrue(start.midi.contains([0xB6, 0x47, 0x7F]), "touch reports on")
        XCTAssertTrue(start.midi.contains([0xB6, 0x46, 0x7F]), "the device's fader pickup on")
        XCTAssertFalse(start.midi.contains([0xBF, 0x05]), "no positions before the device answers")
        XCTAssertEqual(hub.surfaceIDs.count, 4)
        XCTAssertFalse(driver.tick(hub: &hub, now: 1).midi.contains([0x9F, 0x0C, 0x7F]))
        XCTAssertTrue(driver.tick(hub: &hub, now: 3).midi.contains([0x9F, 0x0C, 0x7F]), "asked again after 3 s")

        let answer = driver.receive([0x9F, 0x0C, 0x7F], hub: &hub, now: 4)
        XCTAssertTrue(driver.isConnected)
        XCTAssertTrue(answer.midi.contains([0xB6, 0x1E, 0x01]), "DAW Mixer selected, for the Connect Only setting")
        XCTAssertTrue(answer.midi.contains([0xBF, 0x05, 64]), "fader 1 told its level, for the device's pickup")
        XCTAssertTrue(answer.midi.contains([0xBF, 0x0D, 64]), "encoder 1 (pan) told the middle")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x0D, 5]), "Keys is red in TotalMix")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x0E, 3]), "Vox is white")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x11, 0]), "a blank strip's encoder is dark")
        XCTAssertTrue(answer.midi.contains(LaunchControlOutgoing.text(.stationary, field: 0, "Sources 1-4") ?? []))
        XCTAssertTrue(answer.midi.contains(LaunchControlOutgoing.text(.control(.fader(0)), field: 0, "Keys") ?? []))
        XCTAssertTrue(answer.midi.contains(LaunchControlOutgoing.text(.control(.fader(0)), field: 1, "Level") ?? []))
        XCTAssertTrue(answer.midi.contains(LaunchControlOutgoing.text(.control(.encoder(row: 1, column: 0)), field: 1, "> Phones") ?? []))
        XCTAssertTrue(answer.midi.contains([0xB0, 0x25, 15]), "top buttons: PFL off, dark yellow")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x2D, 7]), "bottom buttons: mute off, dark red")
        XCTAssertTrue(answer.midi.contains([0xB0, 0x6B, 0]), "no next page with four sources")
    }

    func testXL3LayersBindFadersRowsAndButtons() {
        let (driver, hub, _) = connected(layout: .xl3)
        let keys = ChannelRef(.input, 0)
        XCTAssertEqual(hub.strips(of: driver.id(.faders))?[0].knobTarget, .level(keys, submix: 0))
        XCTAssertEqual(hub.strips(of: driver.id(.faders))?[0].switchTarget, .pfl(keys))
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .pan(keys, submix: 0))
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].switchTarget, .mute(keys))
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].knobTarget, .level(keys, submix: 2), "send 1: Phones")
        XCTAssertNil(hub.strips(of: driver.id(.row2))?[0].knobTarget, "send 2: there is none")
    }

    func testXL3ControlsReachTotalMix() {
        var (driver, hub, _) = connected(layout: .xl3)
        let fader = driver.receive([0xBF, 0x05, 64], hub: &hub, now: 1)
        XCTAssertEqual(fader.core.messages, [TotalMixCommand.setMix(from: .input, 0, to: 0, "faderlin", 0.5)],
                       "fader 1 at the level it was sent is caught")

        let pan = driver.receive([0xBF, 0x0D, 127], hub: &hub, now: 2)
        XCTAssertEqual(pan.core.messages.count, 1)
        XCTAssertTrue(pan.midi.contains(LaunchControlOutgoing.text(.control(.encoder(row: 0, column: 0)), field: 2, ValueText.pan(1)) ?? []))

        let pfl = driver.receive([0xB0, 0x25, 0x7F], hub: &hub, now: 3)
        XCTAssertEqual(pfl.core.messages, [TotalMixCommand.set(.input, 0, "pfl", 1)])
        XCTAssertTrue(pfl.midi.contains([0xB0, 0x25, 13]), "PFL on: yellow")
        XCTAssertEqual(driver.receive([0xB0, 0x25, 0x00], hub: &hub, now: 3.1).core.messages, [], "a release does nothing")

        let mute = driver.receive([0xB0, 0x2D, 0x7F], hub: &hub, now: 4)
        XCTAssertEqual(mute.core.messages, [TotalMixCommand.set(.input, 0, "mute", 1)])
        XCTAssertTrue(mute.midi.contains([0xB0, 0x2D, 5]), "mute on: red")
    }

    func testFaderAwayFromItsLevelIsHeldBack() {
        var (driver, hub, _) = connected(layout: .xl3)
        XCTAssertEqual(driver.receive([0xBF, 0x05, 10], hub: &hub, now: 1).core.messages, [],
                       "the hub's pickup holds a fader the device didn't hold")
    }

    func testShiftAndPageSwitchViewsAndPageDownStopsAtTheEnd() {
        var (driver, hub, _) = connected(layout: .xl3)
        XCTAssertTrue(driver.receive([0xB0, 0x6B, 0x7F], hub: &hub, now: 1).midi.isEmpty, "one page of sources only")
        _ = driver.receive([0xB6, 0x3F, 0x7F], hub: &hub, now: 2)
        let outputs = driver.receive([0xB0, 0x6B, 0x7F], hub: &hub, now: 2)
        XCTAssertEqual(driver.view, .outputs)
        XCTAssertTrue(outputs.midi.contains(LaunchControlOutgoing.text(.stationary, field: 0, "Outputs 1-2") ?? []))
        XCTAssertEqual(hub.strips(of: driver.id(.faders))?[0].knobTarget, .level(ChannelRef(.output, 0), submix: nil))
        _ = driver.receive([0xB6, 0x3F, 0x00], hub: &hub, now: 3)
        _ = driver.receive([0xB0, 0x6A, 0x7F], hub: &hub, now: 3)
        XCTAssertEqual(driver.view, .outputs, "Page up without Shift pages; it doesn't switch views")
    }

    func testRowFunctionsAndTrackStepTheSends() {
        var (driver, hub, _) = connected(layout: .xl3)
        let keys = ChannelRef(.input, 0)
        XCTAssertTrue(driver.receive([0xB0, 0x66, 0x7F], hub: &hub, now: 1).midi.isEmpty,
                      "Track >: two send rows and one send target, so nothing to step")
        _ = driver.setRowFunctions([.send, .pan, .pan], hub: &hub, now: 2)
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 2))
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].knobTarget, .pan(keys, submix: 0))
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].switchTarget, .mute(keys), "the bottom buttons stay mute")
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
        XCTAssertTrue(midi.contains([0xB0, 0x41, LaunchControlDriver.functionIdle]))

        let track = driver.receive([0xB0, 0x66, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .level(keys, submix: 2), "Track >: send 1")
        XCTAssertTrue(track.midi.contains(LaunchControlOutgoing.text(.overlay, field: 1, "> Phones", model: .lc3) ?? []))
        XCTAssertTrue(driver.receive([0xB0, 0x66, 0x7F], hub: &hub, now: 2).midi.isEmpty, "no second send")
        _ = driver.receive([0xB0, 0x67, 0x7F], hub: &hub, now: 3)
        XCTAssertEqual(hub.strips(of: driver.id(.row0))?[0].knobTarget, .pan(keys, submix: 0), "Track <: back to pan")

        let function = driver.receive([0xB0, 0x41, 0x7F], hub: &hub, now: 4)
        XCTAssertTrue(driver.buttonsArePFL)
        XCTAssertEqual(hub.strips(of: driver.id(.row1))?[0].switchTarget, .pfl(keys))
        XCTAssertTrue(function.midi.contains([0xB0, 0x41, LaunchControlDriver.pflOn]), "Function lit yellow")
        XCTAssertTrue(function.midi.contains([0xB0, 0x25, LaunchControlDriver.pflOff]), "buttons dark yellow")
        XCTAssertEqual(driver.receive([0xB0, 0x25, 0x7F], hub: &hub, now: 5).core.messages,
                       [TotalMixCommand.set(.input, 0, "pfl", 1)])
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
        XCTAssertTrue(driver.buttonsArePFL, "Solo/Arm stands in for Function")
    }

    func testACustomModeStopsDrawingAndDAWMixerDrawsAgain() {
        var (driver, hub, _) = connected(layout: .xl3)
        _ = driver.receive([0xB6, 0x1E, 0x06], hub: &hub, now: 1)
        let change = hub.handle(.mix(bus: .input, channel: 0, output: 0, parameter: "faderlin", value: .number(0.25)), now: 2)
        XCTAssertTrue(driver.take(change, hub: hub).midi.isEmpty, "nothing drawn in a Custom Mode")
        let back = driver.receive([0xB6, 0x1E, 0x01], hub: &hub, now: 3)
        XCTAssertTrue(back.midi.contains([0xBF, 0x05, LaunchControlDriver.value(0.25)]), "everything sent again")
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
        XCTAssertEqual(LaunchControlDriver.shortName("Mic 1 long"), "Mic 1")
        XCTAssertEqual(LaunchControlDriver.shortName("AB CDE"), "AB CD")
        XCTAssertEqual(LaunchControlDriver.shortName("Keys Left"), "Keys")
    }
}
