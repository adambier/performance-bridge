import XCTest
import OSCCodec
import TotalMixOSC
import OXIE16
import SurfaceCore
@testable import E16Driver

/// Inputs 1/2 ("Keys", stereo, red), 3 ("Vox"), 4 ("Gtr"); playbacks 1/2 ("Tracks", stereo);
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

private let ack: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x53, 0xF7]
private let labelsID: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x03]
private let ringsID: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x04]

private extension Array where Element == UInt8 {
    func contains(_ part: [UInt8]) -> Bool {
        guard !part.isEmpty, part.count <= count else { return part.isEmpty }
        return (0...(count - part.count)).contains { Array(self[$0..<$0 + part.count]) == part }
    }

    /// The SysEx messages in these bytes.
    var sysExMessages: [[UInt8]] {
        var messages: [[UInt8]] = []
        var current: [UInt8]?
        for byte in self {
            if byte == 0xF0 { current = [byte] } else if var c = current {
                c.append(byte)
                if byte == 0xF7 { messages.append(c); current = nil } else { current = c }
            }
        }
        return messages
    }

    /// The title of the last LABELS message, if any.
    var lastTitle: String? {
        guard let labels = sysExMessages.last(where: { $0.starts(with: labelsID) }) else { return nil }
        let raw = E16Outgoing.unpack(Array(labels[8..<(labels.count - 1)]))
        return String(decoding: raw[0..<16], as: UTF8.self)
    }

    /// The labels of the last LABELS message, if any.
    var lastLabels: [String]? {
        guard let labels = sysExMessages.last(where: { $0.starts(with: labelsID) }) else { return nil }
        let raw = E16Outgoing.unpack(Array(labels[8..<(labels.count - 1)]))
        return (0..<16).map { String(decoding: raw[(16 + $0 * 4)..<(20 + $0 * 4)], as: UTF8.self) }
    }

    /// The rings set by the RING messages, by encoder, last one wins.
    var rings: [Int: (r: UInt8, g: UInt8, b: UInt8, amount: Int, bipolar: Bool)] {
        var rings: [Int: (r: UInt8, g: UInt8, b: UInt8, amount: Int, bipolar: Bool)] = [:]
        for message in sysExMessages where message.starts(with: ringsID) {
            let raw = E16Outgoing.unpack(Array(message[8..<(message.count - 1)]))
            var i = 0
            while i + 7 <= raw.count {
                rings[Int(raw[i])] = (raw[i + 1], raw[i + 2], raw[i + 3], Int(raw[i + 4]) << 7 | Int(raw[i + 5]), raw[i + 6] == 1)
                i += 7
            }
        }
        return rings
    }
}

private let ledsID: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x01]

private extension Array where Element == UInt8 {
    /// The single LEDs set by the LED messages, by encoder.
    var leds: [Int: [LED]] {
        var leds: [Int: [LED]] = [:]
        for message in sysExMessages where message.starts(with: ledsID) {
            let raw = E16Outgoing.unpack(Array(message[8..<(message.count - 1)]))
            var i = 0
            while i + 5 <= raw.count {
                leds[Int(raw[i]), default: []].append(LED(index: Int(raw[i + 1]), r: raw[i + 2], g: raw[i + 3], b: raw[i + 4]))
                i += 5
            }
        }
        return leds
    }
}

private struct LED: Equatable {
    var index: Int, r: UInt8, g: UInt8, b: UInt8
}

private extension Array where Element == UInt8 {
}

/// A driver that has started and been answered by the device.
private func connected() -> (driver: E16Driver, hub: SurfaceHub, midi: [UInt8]) {
    var hub = loadedHub()
    var driver = E16Driver(name: "e16")
    let start = driver.start(hub: &hub, now: 0)
    let answer = driver.receive(ack, hub: &hub, now: 0)
    return (driver, hub, start.midi + answer.midi)
}

final class E16DriverTests: XCTestCase {
    func testStartAsksForRemoteModeAndDrawsOnceAnswered() {
        var hub = loadedHub()
        var driver = E16Driver(name: "e16")
        let start = driver.start(hub: &hub, now: 0)
        XCTAssertEqual(start.midi, E16Outgoing.enterRemoteMode)
        XCTAssertFalse(driver.isConnected)
        XCTAssertEqual(driver.tick(hub: &hub, now: 0.5).midi, [], "not asked again yet")
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.1).midi, E16Outgoing.enterRemoteMode, "asked again after a second")
        let answer = driver.receive(ack, hub: &hub, now: 1.2)
        XCTAssertTrue(driver.isConnected)
        XCTAssertEqual(answer.midi.lastTitle, "LEVEL           ")
        XCTAssertEqual(answer.midi.lastLabels?.prefix(5), ["Keys", "Vox ", "Gtr ", "PB 1", "    "])
        let rings = answer.midi.rings
        XCTAssertEqual(rings[0]?.r, 127, "Keys is red")
        XCTAssertEqual(rings[0]?.amount, 8192, "at 0.5")
        XCTAssertEqual(rings[0]?.bipolar, false)
        XCTAssertEqual(rings[1]?.r, 127, "Vox is white")
        XCTAssertEqual(rings[1]?.g, 127)
        XCTAssertEqual(rings[4]?.amount, 0, "an empty strip is dark")
        XCTAssertEqual(rings[4]?.r, 0)
        XCTAssertEqual(driver.tick(hub: &hub, now: 5).midi, [], "nothing to send while quiet")
    }

    func testStopGivesTheDeviceBack() {
        var (driver, hub, _) = connected()
        XCTAssertEqual(driver.stop(hub: &hub), E16Outgoing.exitRemoteMode)
        XCTAssertFalse(driver.isConnected)
        XCTAssertNil(hub.mode(of: driver.id(.main)))
    }

    func testTurnMovesTheLevelAndShowsTheValue() {
        var (driver, hub, _) = connected()
        let step = driver.receive([0xB0, 2, 0x04], hub: &hub, now: 1)  // Vox, +4
        XCTAssertEqual(step.core.messages.map(\.address), ["/mix/in/2/0/faderlin"])
        let position = 0.5 + 4 * E16Driver.levelStep
        XCTAssertEqual(step.core.messages.first?.arguments.first, .float(Float(position)))
        XCTAssertEqual(step.midi.rings[1]?.amount, Int((position * 16383).rounded()))
        XCTAssertEqual(step.midi.lastTitle, ("Vox " + ValueText.level(position: position)).padding(toLength: 16, withPad: " ", startingAt: 0))
        // The title goes back to the function after a second.
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.5).midi, [])
        XCTAssertNil(driver.tick(hub: &hub, now: 1.5).midi.lastTitle)
        XCTAssertEqual(driver.tick(hub: &hub, now: 2.1).midi.lastTitle, "LEVEL           ")
        // Counter-clockwise, to the bottom and no further.
        let down = driver.receive([0xB0, 2, 0x78], hub: &hub, now: 3)  // −8
        XCTAssertEqual(down.core.messages.first?.arguments.first, .float(Float(position - 8 * E16Driver.levelStep)))
        for _ in 0..<40 { _ = driver.receive([0xB0, 2, 0x78], hub: &hub, now: 3) }
        let bottom = driver.receive([0xB0, 2, 0x78], hub: &hub, now: 4)
        XCTAssertEqual(bottom.core.messages.first?.arguments.first, .float(0))
        XCTAssertEqual(driver.title(hub: hub), "Vox -oo")
    }

    func testAShortPushMutesOnReleaseAndAHeldPushIsPFL() {
        var (driver, hub, _) = connected()
        let down = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 1)  // push Vox
        XCTAssertEqual(down.core.messages, [], "nothing until release")
        let up = driver.receive([0x80, 1, 0x00], hub: &hub, now: 1.2)
        XCTAssertEqual(up.core.messages.map(\.address), ["/input/2/mute"])
        XCTAssertEqual(up.core.messages.first?.arguments.first, .float(1))
        XCTAssertEqual(up.midi.lastTitle, "Vox MUTE ON     ")
        XCTAssertEqual(up.midi.rings[1]?.amount, 8192, "the fill is kept")
        XCTAssertEqual(up.midi.leds[1]?.map(\.index), [0, 7, 8, 15], "four red marks")
        XCTAssertEqual(up.midi.leds[1]?.first?.r, 127)
        XCTAssertEqual(up.midi.leds[1]?.first?.g, 0)
        // Held: PFL at 0.4 s, and no mute on release.
        _ = driver.receive([0x90, 2, 0x7F], hub: &hub, now: 2)  // push Gtr
        XCTAssertEqual(driver.tick(hub: &hub, now: 2.3).core.messages, [])
        let pfl = driver.tick(hub: &hub, now: 2.45)
        XCTAssertEqual(pfl.core.messages.map(\.address), ["/input/3/pfl"])
        XCTAssertEqual(pfl.midi.lastTitle, "Gtr PFL ON      ")
        XCTAssertEqual(pfl.midi.rings[2]?.amount, 8192)
        XCTAssertEqual(pfl.midi.leds[2]?.map(\.g), pfl.midi.leds[2]?.map { _ in 127 }, "a white LED")
        XCTAssertNil(driver.tick(hub: &hub, now: 4).midi.lastTitle, "the title stays while held")
        XCTAssertEqual(driver.title(hub: hub), "Gtr PFL ON")
        let release = driver.receive([0x80, 2, 0x00], hub: &hub, now: 5)
        XCTAssertEqual(release.core.messages, [], "no mute")
        _ = driver.tick(hub: &hub, now: 6.1)
        XCTAssertEqual(driver.title(hub: hub), "LEVEL           ", "a second after the release")
        // The PFL's LED runs round the ring.
        let later = driver.tick(hub: &hub, now: 6.2)
        XCTAssertEqual(later.midi.leds.keys.sorted(), [2], "only the PFL ring is redrawn")
        XCTAssertEqual(later.midi.leds[2]?.first?.index, Int((6.2 / E16Driver.rotationStep).rounded(.down)) % 16)
        // A second short push turns mute off.
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 7)
        let unmute = driver.receive([0x80, 1, 0x00], hub: &hub, now: 7.1)
        XCTAssertEqual(unmute.core.messages.first?.arguments.first, .float(0))
        XCTAssertEqual(unmute.midi.lastTitle, "Vox MUTE OFF    ")
        XCTAssertEqual(unmute.midi.leds[1], nil)
    }

    func testShiftPageButtons() {
        var (driver, hub, _) = connected()
        let shift = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(shift.midi.lastTitle, "LEVEL           ", "the title stays")
        XCTAssertEqual(shift.midi.lastLabels, ["LEVL", "PAN ", "    ", "    ", "    ", "    ", "    ", "    ",
                                               "    ", "    ", "<OUT", "OUT>", "    ", "    ", "<PG ", "PG> "])
        let rings = shift.midi.rings
        XCTAssertEqual(rings[0]?.g, 57, "LEVEL, in use: medium teal")
        XCTAssertEqual(rings[0]?.amount, 16383)
        XCTAssertEqual(rings[1]?.b, 6, "PAN: dim sky blue")
        XCTAssertEqual(rings[10]?.r, 6, "previous output: dim magenta")
        XCTAssertEqual(rings[2]?.amount, 0, "a blank is dark")
        XCTAssertNil(rings[14], "an empty strip's ring was dark already")
        // A turn does nothing on the Shift page.
        XCTAssertEqual(driver.receive([0xB0, 1, 0x04], hub: &hub, now: 1.1).core.messages, [])
        // PAN.
        let pan = driver.receive([0x90, 1, 0x7F, 0x80, 1, 0x00], hub: &hub, now: 1.2)
        XCTAssertEqual(driver.function, .pan)
        XCTAssertEqual(pan.midi.lastTitle, "PAN             ", "said at once")
        XCTAssertEqual(pan.midi.rings[1]?.b, 57, "now PAN is in use")
        XCTAssertEqual(pan.midi.rings[0]?.g, 6)
        XCTAssertEqual(pan.core.messages, [], "no mute from a button")
        // A button held down is full bright, whatever it does.
        let down = driver.receive([0x90, 15, 0x7F], hub: &hub, now: 1.25)
        XCTAssertEqual(down.midi.rings[15]?.g, 127, "NEXT page, pressed: bright, though it does nothing")
        XCTAssertEqual(driver.receive([0x80, 15, 0x00], hub: &hub, now: 1.26).midi.rings[15]?.amount, 0, "dark again")
        // Next output: the only send, Phones.
        let out = driver.receive([0x90, 11, 0x7F, 0x80, 11, 0x00], hub: &hub, now: 1.3)
        XCTAssertEqual(driver.function, .send(0))
        XCTAssertEqual(out.midi.lastTitle, "> PHONES        ")
        XCTAssertEqual(out.midi.rings[11]?.amount, 0, "no next output: dark once released")
        XCTAssertEqual(out.midi.rings[10]?.amount, 0, "no previous output either: dark")
        XCTAssertEqual(driver.receive([0x90, 11, 0x7F, 0x80, 11, 0x00], hub: &hub, now: 1.4).core.messages, [])
        XCTAssertEqual(driver.function, .send(0), "stays at the last output")
        // Release: the strips come back, in the send's color (white, Phones is white) and values.
        let release = driver.receive([0x90, 16, 0x00], hub: &hub, now: 2)
        XCTAssertEqual(release.midi.lastLabels?.prefix(2), ["Keys", "Vox "])
        XCTAssertEqual(release.midi.rings[0]?.r, 127)
        XCTAssertEqual(release.midi.rings[0]?.amount, 8192)
        XCTAssertEqual(release.midi.lastTitle, "> PHONES        ")
        // A turn now sets the send.
        let turn = driver.receive([0xB0, 1, 0x01], hub: &hub, now: 3)
        XCTAssertEqual(turn.core.messages.map(\.address), ["/mix/in/0/2/faderlin"])
        // Back to LEVEL.
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 0, 0x7F, 0x80, 0, 0x00, 0x90, 16, 0x00], hub: &hub, now: 4)
        XCTAssertEqual(driver.function, .level)
    }

    func testPanTurn() {
        var (driver, hub, _) = connected()
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 1, 0x7F, 0x80, 1, 0x00, 0x90, 16, 0x00], hub: &hub, now: 1)
        XCTAssertEqual(driver.function, .pan)
        let step = driver.receive([0xB0, 1, 0x02], hub: &hub, now: 2)
        XCTAssertEqual(step.core.messages.map(\.address), ["/mix/in/0/0/balpan"])
        XCTAssertEqual(step.core.messages.first?.arguments.first, .float(Float(2 * E16Driver.panStep * 2)))
        XCTAssertEqual(step.midi.lastTitle, "Keys R2         ")
        XCTAssertEqual(step.midi.rings[0]?.bipolar, true)
    }

    func testPageButtons() {
        var hub = loadedHub()
        // Twenty sources: inputs 5–20 join.
        for number in 4..<20 {
            _ = hub.handle(.channel(bus: .input, channel: number, parameter: "name", value: .text("In \(number + 1)")), now: 0)
            _ = hub.handle(.mix(bus: .input, channel: number, output: 0, parameter: "faderlin", value: .number(0.3)), now: 0)
        }
        var driver = E16Driver(name: "e16")
        _ = driver.start(hub: &hub, now: 0)
        let answer = driver.receive(ack, hub: &hub, now: 0)
        XCTAssertEqual(answer.midi.lastTitle, "LEVEL        1/2")
        let shift = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(shift.midi.rings[14]?.amount, 0, "no previous page: dark")
        XCTAssertEqual(shift.midi.rings[15]?.g, 6, "lime, dim")
        let next = driver.receive([0x90, 15, 0x7F, 0x80, 15, 0x00], hub: &hub, now: 1.5)
        XCTAssertEqual(next.midi.lastTitle, "LEVEL        2/2")
        XCTAssertEqual(next.midi.rings[14]?.g, 6, "a previous page now")
        XCTAssertEqual(next.midi.rings[15]?.amount, 0, "no next page")
        let past = driver.receive([0x90, 15, 0x7F, 0x80, 15, 0x00], hub: &hub, now: 1.6)
        XCTAssertNil(past.midi.lastTitle, "nothing past the end")
        XCTAssertEqual(past.midi.rings[15]?.amount, 0, "lit while down, dark again")
        let release = driver.receive([0x90, 16, 0x00], hub: &hub, now: 2)
        XCTAssertEqual(release.midi.lastLabels?.prefix(4), ["In18", "In19", "In20", "PB 1"], "In 18, In 19, In 20, PB 1/2")
        _ = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 3)
        let back = driver.receive([0x90, 14, 0x7F, 0x80, 14, 0x00], hub: &hub, now: 3.5)
        XCTAssertEqual(back.midi.lastTitle, "LEVEL        1/2")
    }

    func testTotalMixChangesRedrawOnlyWhatChanged() {
        var (driver, hub, _) = connected()
        let output = hub.handle(.channel(bus: .input, channel: 2, parameter: "mute", value: .number(1)), now: 1)
        let step = driver.take(output, hub: &hub, now: 1)
        XCTAssertEqual(step.midi.sysExMessages.count, 2, "one ring message and one LED message, no labels")
        XCTAssertEqual(step.midi.rings.keys.sorted(), [1])
        XCTAssertEqual(step.midi.leds[1]?.map(\.index), [0, 7, 8, 15], "muted: the marks")
        let rename = hub.handle(.channel(bus: .input, channel: 2, parameter: "name", value: .text("Vocal")), now: 2)
        let renamed = driver.take(rename, hub: &hub, now: 2)
        XCTAssertEqual(renamed.midi.lastLabels?[1], "Voca")
        XCTAssertEqual(driver.take(CoreOutput(), hub: &hub, now: 3).midi, [], "nothing changed")
    }

    func testMuteFlashesWhileMuteMasterIsOff() {
        var (driver, hub, _) = connected()
        _ = driver.receive([0x90, 1, 0x7F, 0x80, 1, 0x00], hub: &hub, now: 0.1)
        let output = hub.handle(.other(path: "globalmute", value: .number(0)), now: 0.2)
        _ = driver.take(output, hub: &hub, now: 0.2)
        let half = driver.tick(hub: &hub, now: 0.6)
        XCTAssertEqual(half.midi.rings[1]?.amount, 8192)
        XCTAssertEqual(half.midi.leds[1], nil, "the marks are off")
        let back = driver.tick(hub: &hub, now: 1.1)
        XCTAssertEqual(back.midi.leds[1]?.map(\.index), [0, 7, 8, 15], "and on again")
    }

    func testLabelsLoseSpacesBeforeTheirEnd() {
        XCTAssertEqual(E16Driver.fit("PB 11", 4), "PB11")
        XCTAssertEqual(E16Driver.fit("PB 1", 4), "PB 1")
        XCTAssertEqual(E16Driver.fit("ADAT 3/4", 4), "ADAT")
        XCTAssertEqual(E16Driver.fit("PB 1/2", 4), "PB 1")
        XCTAssertEqual(E16Driver.fit("PB 11/12", 4), "PB11")
        XCTAssertEqual(E16Driver.fit("Mic 1/2", 8), "Mic 1/2")
    }

}
