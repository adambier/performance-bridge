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
private let ledsID: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x01]

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
        return Self.text(raw[0..<16])
    }

    /// Text as the device shows it: without its null padding.
    static func text(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// The labels of the last LABELS message, if any.
    var lastLabels: [String]? {
        guard let labels = sysExMessages.last(where: { $0.starts(with: labelsID) }) else { return nil }
        let raw = E16Outgoing.unpack(Array(labels[8..<(labels.count - 1)]))
        return (0..<16).map { Self.text(raw[(16 + $0 * 4)..<(20 + $0 * 4)]) }
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

private extension Array where Element == UInt8 {
    /// The LEDs set by LED messages, by encoder: the LED indices and their colors, in order,
    /// from the last LED message for that encoder (a RING message for an encoder clears its
    /// LEDs, as on the device).
    var leds: [Int: [(led: Int, r: UInt8, g: UInt8, b: UInt8)]] {
        var leds: [Int: [(led: Int, r: UInt8, g: UInt8, b: UInt8)]] = [:]
        for message in sysExMessages {
            let raw = E16Outgoing.unpack(Array(message[8..<(message.count - 1)]))
            if message.starts(with: ringsID) {
                var i = 0
                while i + 7 <= raw.count { leds[Int(raw[i])] = nil; i += 7 }
            } else if message.starts(with: ledsID) {
                var i = 0
                while i + 5 <= raw.count {
                    leds[Int(raw[i]), default: []].append((Int(raw[i + 1]), raw[i + 2], raw[i + 3], raw[i + 4]))
                    i += 5
                }
            }
        }
        return leds
    }
}

/// A driver that has started and been answered by the device.
private func connected() -> (driver: E16Driver, hub: SurfaceHub, midi: [UInt8]) {
    var hub = loadedHub()
    var driver = E16Driver(name: "e16")
    driver.brightness = 1  // the tests read exact values
    driver.drawsScreen = false  // the tests read the firmware's label layout
    let start = driver.start(hub: &hub, now: 0)
    let answer = driver.receive(ack, hub: &hub, now: 0)
    return (driver, hub, start.midi + answer.midi)
}

final class E16DriverTests: XCTestCase {
    /// A level at half the fader's travel, as the ring shows it (0 dB fills the ring).
    static let half = Int((E16Driver.levelAmount(0.5) * 16383).rounded())

    func testStartAsksForRemoteModeAndDrawsOnceAnswered() {
        var hub = loadedHub()
        var driver = E16Driver(name: "e16")
        driver.brightness = 1
        driver.drawsScreen = false
        let start = driver.start(hub: &hub, now: 0)
        XCTAssertEqual(start.midi, E16Outgoing.enterRemoteMode)
        XCTAssertFalse(driver.isConnected)
        XCTAssertEqual(driver.tick(hub: &hub, now: 0.5).midi, [], "not asked again yet")
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.1).midi, E16Outgoing.enterRemoteMode, "asked again after a second")
        let answer = driver.receive(ack, hub: &hub, now: 1.2)
        XCTAssertTrue(driver.isConnected)
        XCTAssertEqual(answer.midi.lastTitle, "LEVEL")
        XCTAssertEqual(answer.midi.lastLabels?.prefix(5), ["Keys", "Vox", "Gtr", "P1/2", ""])
        let rings = answer.midi.rings
        XCTAssertEqual(rings[0]?.r, 127, "Keys is red")
        XCTAssertEqual(rings[0]?.amount, Int((0.5 / FaderCurve.unityPosition * 16383).rounded()), "at 0.5, scaled so 0 dB fills the ring")
        XCTAssertEqual(rings[0]?.bipolar, false)
        XCTAssertEqual(rings[1]?.r, 127, "Vox is white")
        XCTAssertEqual(rings[1]?.g, 127)
        XCTAssertEqual(rings[4]?.amount, 0, "an empty strip is dark")
        XCTAssertEqual(rings[4]?.r, 0)
        // A level fills the ring at 0 dB and above, and a strip with a channel never goes dark.
        let unity = driver.take(hub.handle(.mix(bus: .input, channel: 2, output: 0, parameter: "faderlin", value: .number(FaderCurve.unityPosition)), now: 2), hub: &hub, now: 2)
        XCTAssertEqual(unity.midi.rings[1]?.amount, 16383, "full at 0 dB")
        let top = driver.take(hub.handle(.mix(bus: .input, channel: 2, output: 0, parameter: "faderlin", value: .number(1)), now: 2.5), hub: &hub, now: 2.5)
        XCTAssertNil(top.midi.rings[1], "still full above 0 dB: nothing new to send")
        let bottom = driver.take(hub.handle(.mix(bus: .input, channel: 2, output: 0, parameter: "faderlin", value: .number(0)), now: 3), hub: &hub, now: 3)
        XCTAssertEqual(bottom.midi.rings[1]?.amount, Int((1.0 / 16 * 16383).rounded()), "one LED at -oo")
        XCTAssertEqual(driver.tick(hub: &hub, now: 5).midi, [], "nothing to send while quiet")
    }

    func testSetOnlyMuteWithPFL() {
        // While Mute Master is off, a set mute's marks turn with PFL's and blink; the level
        // does not show (Tier 1 review, 2026-11-05).
        var (driver, hub, _) = connected()
        _ = driver.take(hub.handle(.other(path: "globalmute", value: .number(0)), now: 0.05), hub: &hub, now: 0.05)
        _ = driver.receive([0x90, 1, 0x7F, 0x80, 1, 0x00], hub: &hub, now: 0.1)  // mute set, not in effect
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 1)
        _ = driver.tick(hub: &hub, now: 2.05)  // PFL on
        _ = driver.receive([0x80, 1, 0x00], hub: &hub, now: 2.1)
        let lit = driver.tick(hub: &hub, now: 3.05).midi
        XCTAssertEqual(lit.rings[1]?.amount, 0)
        XCTAssertEqual(lit.leds[1]?.count, 8)
        let unlit = driver.tick(hub: &hub, now: 3.55).midi
        XCTAssertEqual(unlit.rings[1]?.amount, 0, "not the level")
        XCTAssertEqual(unlit.leds[1]?.count, 4)
        XCTAssertEqual(unlit.leds[1]?.filter { $0.b != 0 }.count, 4, "the pink marks alone")
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
        XCTAssertEqual(step.midi.rings[1]?.amount, Int((E16Driver.levelAmount(position) * 16383).rounded()))
        XCTAssertEqual(step.midi.lastTitle, "Vox " + ValueText.level(position: position))
        // The title goes back to the function after a second.
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.5).midi, [])
        XCTAssertNil(driver.tick(hub: &hub, now: 1.5).midi.lastTitle)
        XCTAssertEqual(driver.tick(hub: &hub, now: 2.1).midi.lastTitle, "LEVEL")
        // Counter-clockwise, to the bottom and no further.
        let down = driver.receive([0xB0, 2, 0x78], hub: &hub, now: 3)  // −8
        XCTAssertEqual(down.core.messages.first?.arguments.first, .float(Float(position - 8 * E16Driver.levelStep)))
        for _ in 0..<40 { _ = driver.receive([0xB0, 2, 0x78], hub: &hub, now: 3) }
        let bottom = driver.receive([0xB0, 2, 0x78], hub: &hub, now: 4)
        XCTAssertEqual(bottom.core.messages.first?.arguments.first, .float(0))
        XCTAssertEqual(driver.title(hub: hub), "Vox -oo")
        XCTAssertEqual(driver.look(1, hub: hub).ring.amount, 1.0 / 16, "one LED at -oo")
    }

    func testAShortPushMutesOnReleaseAndAHeldPushIsPFL() {
        var (driver, hub, _) = connected()
        let down = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 1)  // push Vox
        XCTAssertEqual(down.core.messages, [], "nothing until release")
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.1).midi, [], "a tap draws no countdown")
        let up = driver.receive([0x80, 1, 0x00], hub: &hub, now: 1.2)
        XCTAssertEqual(up.core.messages.map(\.address), ["/input/2/mute"])
        XCTAssertEqual(up.core.messages.first?.arguments.first, .float(1))
        XCTAssertEqual(up.midi.lastTitle, "Vox MUTE ON")
        // Muted: a dark ring with four orange marks a quarter ring apart, which rotate (Adam,
        // 2026-11-05).
        XCTAssertEqual(up.midi.rings[1]?.amount, 0, "the ring dark under the marks")
        let marks = up.midi.leds[1] ?? []
        XCTAssertEqual(marks.count, 4, "four marks")
        XCTAssertEqual(Set(marks.map { ($0.led - (marks.first?.led ?? 0) + 16) % 16 }), [0, 4, 8, 12], "a quarter ring apart")
        XCTAssertEqual(marks.first?.g, E16Driver.muteRGB.1, "orange marks")
        let turned = driver.tick(hub: &hub, now: 1.2 + E16Driver.rotationStep * 2)
        XCTAssertEqual(turned.midi.leds[1]?.count, 4, "the marks move with time")
        XCTAssertNotEqual(turned.midi.leds[1]?.map(\.led), marks.map(\.led))
        // Held: nothing in the tap window, then a countdown, PFL at 1 s, and no mute on release.
        _ = driver.receive([0x90, 2, 0x7F], hub: &hub, now: 2)  // push Gtr
        XCTAssertEqual(driver.tick(hub: &hub, now: 2.2).midi.lastTitle, "LEVEL", "the tap window: only the mute's overlay ends")
        let counting = driver.tick(hub: &hub, now: 2.55)
        XCTAssertEqual(counting.core.messages, [])
        XCTAssertEqual(counting.midi.lastTitle, "Gtr -> PFL")
        XCTAssertEqual(counting.midi.rings[2]?.r, E16Driver.pflRGB.0, "a pink arc")
        XCTAssertEqual(counting.midi.rings[2]?.amount, Int((0.3 / 0.75 * 16383).rounded()), "0.3 s of the 0.75 s sweep")
        let pfl = driver.tick(hub: &hub, now: 3.05)
        XCTAssertEqual(pfl.core.messages.map(\.address), ["/input/3/pfl"])
        XCTAssertEqual(driver.title(hub: hub), "Gtr PFL ON")
        XCTAssertEqual(pfl.midi.rings[2]?.amount, 0, "a dark ring")
        XCTAssertEqual(pfl.midi.leds[2]?.count, 4, "four pink marks")
        XCTAssertEqual(pfl.midi.leds[2]?.first?.b, E16Driver.pflRGB.2)
        XCTAssertNil(driver.tick(hub: &hub, now: 4.5).midi.lastTitle, "the title stays while held")
        XCTAssertEqual(driver.title(hub: hub), "Gtr PFL ON")
        let release = driver.receive([0x80, 2, 0x00], hub: &hub, now: 5)
        XCTAssertEqual(release.core.messages, [], "no mute")
        _ = driver.tick(hub: &hub, now: 6.1)
        XCTAssertEqual(driver.title(hub: hub), "LEVEL       PFL", "a second after the release, with the PFL marker")
        // PFL's marks rotate, as a mute's do (Adam, 2026-11-05).
        let a = driver.tick(hub: &hub, now: 6.85).midi.leds[2]?.map(\.led)
        let b = driver.tick(hub: &hub, now: 7.15).midi.leds[2]?.map(\.led)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotEqual(a, b, "the pink marks turn")
        // Holding again counts down the other way and turns PFL off.
        _ = driver.receive([0x90, 2, 0x7F], hub: &hub, now: 8)
        let reverse = driver.tick(hub: &hub, now: 8.65)
        XCTAssertEqual(reverse.midi.lastTitle, "Gtr -> PFL OFF")
        XCTAssertEqual(reverse.midi.rings[2]?.amount, Int((1 - 0.4 / 0.75) * 16383 + 0.5), "shrinking")
        let off = driver.tick(hub: &hub, now: 9.05)
        XCTAssertEqual(off.core.messages.first?.arguments.first, .float(0))
        XCTAssertEqual(driver.title(hub: hub), "Gtr PFL OFF")
        _ = driver.receive([0x80, 2, 0x00], hub: &hub, now: 9.1)
        _ = driver.tick(hub: &hub, now: 10.2)
        XCTAssertEqual(driver.title(hub: hub), "LEVEL", "no PFL marker")
        // A push let go during the countdown is a mute, and the countdown is gone.
        _ = driver.receive([0x90, 3, 0x7F], hub: &hub, now: 11)  // push Tracks
        _ = driver.tick(hub: &hub, now: 11.5)
        let short = driver.receive([0x80, 3, 0x00], hub: &hub, now: 11.6)
        XCTAssertEqual(short.core.messages.map(\.address), ["/playback/0/mute"])
        XCTAssertEqual(short.midi.lastTitle, "PB 1/2 MUTE ON")
        XCTAssertEqual(short.midi.leds[3]?.count, 4, "the mute's marks, no arc")
        XCTAssertEqual(short.midi.leds[3]?.first?.g, E16Driver.muteRGB.1, "orange")
        // A second short push turns mute off, and the level is back.
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 12)
        let unmute = driver.receive([0x80, 1, 0x00], hub: &hub, now: 12.1)
        XCTAssertEqual(unmute.core.messages.first?.arguments.first, .float(0))
        XCTAssertEqual(unmute.midi.lastTitle, "Vox MUTE OFF")
        XCTAssertEqual(unmute.midi.rings[1]?.amount, Self.half, "the fill again")
        XCTAssertEqual(unmute.midi.rings[1]?.g, 127, "in the channel's color")
    }

    /// The marks are orange on every channel: nothing is drawn under them (Adam, 2026-11-05).
    func testMuteMarksAreOrangeOnEveryChannel() {
        var (driver, hub, _) = connected()
        let red = driver.receive([0x90, 0, 0x7F, 0x80, 0, 0x00], hub: &hub, now: 1)  // mute Keys, red
        XCTAssertEqual(red.midi.rings[0]?.amount, 0, "dark under the marks")
        XCTAssertEqual(red.midi.leds[0]?.first.map { [$0.r, $0.g, $0.b] }, [E16Driver.muteRGB.0, E16Driver.muteRGB.1, E16Driver.muteRGB.2])
        let unmute = driver.receive([0x90, 0, 0x7F, 0x80, 0, 0x00], hub: &hub, now: 2)
        XCTAssertEqual(unmute.midi.rings[0]?.r, 127, "the level back, in red")
        XCTAssertNil(unmute.midi.leds[0], "no marks")
    }

    /// Push-and-turn is pan (level in PAN mode), and cancels the push: no mute on release, no
    /// PFL however long it is held (test 6; Adam, 2026-11-05).
    func testPushAndTurnPansAndCancelsThePush() {
        var (driver, hub, _) = connected()
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 1)  // push Vox
        let turn = driver.receive([0xB0, 2, UInt8(E16Driver.panCenterUnits + 1)], hub: &hub, now: 1.1)  // past the sticky center
        XCTAssertEqual(turn.core.messages.map(\.address), ["/mix/in/2/0/balpan"], "pan, in LEVEL mode")
        XCTAssertEqual(turn.midi.rings[1]?.bipolar, true, "the ring shows the pan")
        XCTAssertEqual(turn.midi.rings[1].map { [$0.r, $0.g, $0.b] }, [127, 0, 0], "red off center, however little")
        let shown = Double(turn.midi.rings[1]?.amount ?? 8192) / 16383
        XCTAssertGreaterThanOrEqual(abs(shown - 0.5), E16Driver.panMinimumOffset - 0.001, "and at least one LED from the top")
        XCTAssertTrue(driver.title(hub: hub).hasPrefix("Vox "), "and the title its value")
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.5).midi, [], "no countdown")
        let late = driver.tick(hub: &hub, now: 2.2)
        XCTAssertFalse(late.core.messages.contains { $0.address.hasSuffix("/pfl") }, "no PFL after a second")
        let up = driver.receive([0x80, 1, 0x00], hub: &hub, now: 2.3)
        XCTAssertEqual(up.core.messages, [], "no mute on release")
        XCTAssertEqual(up.midi.rings[1]?.bipolar, false, "the ring back to the level")
        // A plain turn is the level again.
        XCTAssertEqual(driver.receive([0xB0, 2, 0x01], hub: &hub, now: 2.5).core.messages.map(\.address), ["/mix/in/2/0/faderlin"])
        // A turn after the countdown has begun cancels it.
        _ = driver.receive([0x90, 2, 0x7F], hub: &hub, now: 3)  // push Gtr
        _ = driver.tick(hub: &hub, now: 3.4)
        XCTAssertEqual(driver.title(hub: hub), "Gtr -> PFL")
        _ = driver.receive([0xB0, 3, 0x01], hub: &hub, now: 3.5)
        XCTAssertFalse(driver.title(hub: hub).contains("PFL"))
        XCTAssertEqual(driver.receive([0x80, 2, 0x00], hub: &hub, now: 4.5).core.messages, [])
        // In PAN mode, push-and-turn is the level.
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 1, 0x7F, 0x80, 1, 0x00, 0x90, 16, 0x00], hub: &hub, now: 5)  // Shift + 2
        XCTAssertEqual(driver.function, .pan)
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 6)
        XCTAssertEqual(driver.receive([0xB0, 2, 0x01], hub: &hub, now: 6.1).core.messages.map(\.address), ["/mix/in/2/0/faderlin"])
    }

    func testMuteAndPFLTogether() {
        var (driver, hub, _) = connected()
        _ = driver.receive([0x90, 1, 0x7F, 0x80, 1, 0x00], hub: &hub, now: 1)  // mute Vox
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 2)
        let on = driver.tick(hub: &hub, now: 3.05)  // PFL on
        // Both: eight marks on a dark ring, orange and pink interleaved two LEDs apart.
        XCTAssertEqual(on.midi.rings[1]?.amount, 0)
        let marks = on.midi.leds[1] ?? []
        XCTAssertEqual(marks.count, 8)
        let orange = marks.filter { $0.b == 0 }.map(\.led), pink = marks.filter { $0.b != 0 }.map(\.led)
        XCTAssertEqual(orange.count, 4)
        XCTAssertEqual(pink.count, 4)
        XCTAssertEqual(Set(pink), Set(orange.map { ($0 + 2) % 16 }))
    }


    func testShiftPageButtons() {
        var (driver, hub, _) = connected()
        let shift = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(shift.midi.lastTitle, "LEVEL", "the title stays")
        XCTAssertEqual(shift.midi.lastLabels, ["LVL", "PAN", "SEND", "", "", "", "", "",
                                               "", "", "<SND", "SND>", "", "", "", ""],
                       "one page: no page arrows")
        let rings = shift.midi.rings
        XCTAssertEqual(rings[0]?.g, 127, "LEVEL, in use: white at the driver's brightness (1 in the tests)")
        XCTAssertEqual(rings[0]?.amount, 16383)
        XCTAssertEqual(rings[1]?.r, 2, "PAN: magenta at the available level")
        XCTAssertEqual(rings[1]?.b, 2)
        XCTAssertEqual(rings[1]?.amount, 16383)
        XCTAssertEqual(rings[2]?.g, 2, "SEND: green at the available level")
        XCTAssertEqual(rings[10]?.g, 2, "either arrow enters SEND mode at the last output used")
        XCTAssertEqual(rings[11]?.g, 2)
        XCTAssertEqual(rings[3]?.amount, 0, "a blank is dark")
        XCTAssertNil(rings[14], "no pages: an empty strip's ring was dark already")
        // A turn does nothing on the Shift page.
        XCTAssertEqual(driver.receive([0xB0, 1, 0x04], hub: &hub, now: 1.1).core.messages, [])
        // PAN.
        let pan = driver.receive([0x90, 1, 0x7F, 0x80, 1, 0x00], hub: &hub, now: 1.2)
        XCTAssertEqual(driver.function, .pan)
        XCTAssertEqual(pan.midi.lastTitle, "PAN", "said at once")
        XCTAssertEqual(pan.midi.rings[1]?.r, 127, "now PAN is in use")
        XCTAssertEqual(pan.midi.rings[0]?.g, 2, "and LEVEL available")
        XCTAssertEqual(pan.core.messages, [], "no mute from a button")
        // A button that goes nowhere stays dark, pressed or not (review of 2026-11-04); one
        // that goes somewhere is its color at full while held, whatever the brightness.
        let down = driver.receive([0x90, 15, 0x7F], hub: &hub, now: 1.25)
        XCTAssertNil(down.midi.rings[15], "NEXT page, pressed: still dark, it goes nowhere")
        _ = driver.receive([0x80, 15, 0x00], hub: &hub, now: 1.26)
        let sendDown = driver.receive([0x90, 2, 0x7F], hub: &hub, now: 1.27)
        XCTAssertEqual(sendDown.midi.rings[2]?.g, 127, "SEND pressed: the deep green (0,60,0) brought to 127")
        XCTAssertEqual(sendDown.midi.rings[2]?.amount, 16383)
        _ = driver.receive([0x80, 2, 0x00], hub: &hub, now: 1.28)
        _ = driver.receive([0x90, 0, 0x7F, 0x80, 0, 0x00], hub: &hub, now: 1.29)  // back to LEVEL
        _ = driver.receive([0x90, 1, 0x7F, 0x80, 1, 0x00], hub: &hub, now: 1.295)  // and PAN, as before
        // Next output: the only send, Phones; the arrow enters SEND mode.
        let out = driver.receive([0x90, 11, 0x7F, 0x80, 11, 0x00], hub: &hub, now: 1.3)
        XCTAssertEqual(driver.function, .send(0))
        XCTAssertEqual(out.midi.lastTitle, "> PHONES")
        XCTAssertEqual(out.midi.rings[2]?.g, 60, "SEND in use")
        XCTAssertEqual(out.midi.rings[11]?.amount, 0, "no next output: dark once released")
        XCTAssertEqual(out.midi.rings[10]?.amount, 0, "no previous output either")
        XCTAssertEqual(driver.receive([0x90, 11, 0x7F, 0x80, 11, 0x00], hub: &hub, now: 1.4).core.messages, [])
        XCTAssertEqual(driver.function, .send(0), "stays at the last output")
        // Release: the strips come back, in the send's color (white, Phones is white) and values.
        let release = driver.receive([0x90, 16, 0x00], hub: &hub, now: 2)
        XCTAssertEqual(release.midi.lastLabels?.prefix(2), ["Keys", "Vox"])
        XCTAssertEqual(release.midi.rings[0]?.r, 127)
        XCTAssertEqual(release.midi.rings[0]?.amount, Self.half)
        XCTAssertEqual(release.midi.lastTitle, "> PHONES")
        // A turn now sets the send.
        let turn = driver.receive([0xB0, 1, 0x01], hub: &hub, now: 3)
        XCTAssertEqual(turn.core.messages.map(\.address), ["/mix/in/0/2/faderlin"])
        // LEVEL, then SEND goes back to Phones.
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 0, 0x7F, 0x80, 0, 0x00], hub: &hub, now: 4)
        XCTAssertEqual(driver.function, .level)
        _ = driver.receive([0x90, 2, 0x7F, 0x80, 2, 0x00, 0x90, 16, 0x00], hub: &hub, now: 4.1)
        XCTAssertEqual(driver.function, .send(0))
    }

    func testPanTurn() {
        var (driver, hub, _) = connected()
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 1, 0x7F, 0x80, 1, 0x00, 0x90, 16, 0x00], hub: &hub, now: 1)
        XCTAssertEqual(driver.function, .pan)
        let step = driver.receive([0xB0, 1, UInt8(E16Driver.panCenterUnits + 2)], hub: &hub, now: 2)  // two units past center
        XCTAssertEqual(step.core.messages.map(\.address), ["/mix/in/0/0/balpan"])
        XCTAssertEqual(step.core.messages.first?.arguments.first, .float(Float(2 * E16Driver.panStep * 2)))
        XCTAssertEqual(step.midi.lastTitle, "Keys R2")
        XCTAssertEqual(step.midi.rings[0]?.bipolar, true)
    }

    func testPanCenterIsSticky() {
        var (driver, hub, _) = connected()
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 1, 0x7F, 0x80, 1, 0x00, 0x90, 16, 0x00], hub: &hub, now: 1)  // PAN
        let units = E16Driver.panCenterUnits
        func turn(_ delta: Int, _ now: Double) -> String {
            _ = driver.receive([0xB0, 1, UInt8(delta < 0 ? 128 + delta : delta)], hub: &hub, now: now)
            return driver.title(hub: hub)
        }
        XCTAssertEqual(turn(units, 2), "Keys C", "held at center for \(units) units")
        XCTAssertEqual(turn(1, 2.1), "Keys R1", "the next unit moves it")
        XCTAssertEqual(turn(-8, 2.2), "Keys C", "a fast turn back stops at center")
        XCTAssertEqual(turn(-(units - 1), 2.3), "Keys C")
        XCTAssertEqual(turn(2, 2.4), "Keys C", "a turn the other way starts the count again")
        XCTAssertEqual(turn(units - 1, 2.5), "Keys R1", "\(units + 1) units that way, in all")
        XCTAssertEqual(turn(8, 2.6), "Keys R9")
        XCTAssertEqual(turn(-20, 2.7), "Keys C", "crossing from the right stops at center too")
        XCTAssertEqual(turn(-(units + 3), 2.8), "Keys L3")
        // Amounts side by side, for trying them: encoder 2 (index 1) takes the second.
        driver.panCenterTrial = [0, 8]
        XCTAssertEqual(turn(8, 2.9), "Keys C", "crossing still stops at center")
        XCTAssertEqual(turn(2, 2.92), "Keys R2", "encoder 1 takes 0: no units held")
        _ = driver.receive([0xB0, 2, 0x08], hub: &hub, now: 2.95)
        XCTAssertTrue(driver.title(hub: hub).hasSuffix(" C"), "encoder 2 held for 8 units")
        _ = driver.receive([0xB0, 2, 0x01], hub: &hub, now: 2.97)
        XCTAssertTrue(driver.title(hub: hub).hasSuffix(" R1"))
        // A level has no sticky point.
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 0, 0x7F, 0x80, 0, 0x00, 0x90, 16, 0x00], hub: &hub, now: 3)  // LEVEL
        let level = driver.receive([0xB0, 1, 0x01], hub: &hub, now: 3.1)
        XCTAssertEqual(level.core.messages.map(\.address), ["/mix/in/0/0/faderlin"])
    }

    func testPageButtons() {
        var hub = loadedHub()
        // Twenty sources: inputs 5–20 join.
        for number in 4..<20 {
            _ = hub.handle(.channel(bus: .input, channel: number, parameter: "name", value: .text("In \(number + 1)")), now: 0)
            _ = hub.handle(.mix(bus: .input, channel: number, output: 0, parameter: "faderlin", value: .number(0.3)), now: 0)
        }
        var driver = E16Driver(name: "e16")
        driver.brightness = 1
        driver.drawsScreen = false
        _ = driver.start(hub: &hub, now: 0)
        let answer = driver.receive(ack, hub: &hub, now: 0)
        XCTAssertEqual(answer.midi.lastTitle, "LEVEL       1/2")
        let shift = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(shift.midi.rings[14]?.amount, 0, "no previous page: dark")
        XCTAssertEqual(shift.midi.rings[15]?.b, 2, "blue, available")
        let next = driver.receive([0x90, 15, 0x7F, 0x80, 15, 0x00], hub: &hub, now: 1.5)
        XCTAssertEqual(next.midi.lastTitle, "LEVEL       2/2")
        XCTAssertEqual(next.midi.rings[14]?.b, 2, "a previous page now")
        XCTAssertEqual(next.midi.rings[15]?.amount, 0, "no next page")
        let past = driver.receive([0x90, 15, 0x7F, 0x80, 15, 0x00], hub: &hub, now: 1.6)
        XCTAssertNil(past.midi.lastTitle, "nothing past the end")
        XCTAssertNil(past.midi.rings[15], "dark while down too")
        let release = driver.receive([0x90, 16, 0x00], hub: &hub, now: 2)
        XCTAssertEqual(release.midi.lastLabels?.prefix(4), ["In18","In19","In20","P1/2"],"In 18, In 19, In 20, PB 1/2")
        _ = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 3)
        let back = driver.receive([0x90, 14, 0x7F, 0x80, 14, 0x00], hub: &hub, now: 3.5)
        XCTAssertEqual(back.midi.lastTitle, "LEVEL       1/2")
    }

    func testTotalMixChangesRedrawOnlyWhatChanged() {
        var (driver, hub, _) = connected()
        let output = hub.handle(.channel(bus: .input, channel: 2, parameter: "mute", value: .number(1)), now: 1)
        let step = driver.take(output, hub: &hub, now: 1)
        XCTAssertEqual(step.midi.sysExMessages.count, 2, "one ring message and one LED message, no labels")
        XCTAssertEqual(step.midi.rings.keys.sorted(), [1])
        XCTAssertEqual(step.midi.leds.keys.sorted(), [1], "muted: the marks")
        let rename = hub.handle(.channel(bus: .input, channel: 2, parameter: "name", value: .text("Vocal")), now: 2)
        let renamed = driver.take(rename, hub: &hub, now: 2)
        XCTAssertEqual(renamed.midi.lastLabels?[1], "Voca")
        XCTAssertEqual(driver.take(CoreOutput(), hub: &hub, now: 3).midi, [], "nothing changed")
    }

    func testMuteFlashesWhileMuteMasterIsOff() {
        var (driver, hub, _) = connected()
        _ = driver.receive([0x90, 1, 0x7F, 0x80, 1, 0x00], hub: &hub, now: 0.1)
        XCTAssertEqual(driver.title(hub: hub), "Vox MUTE ON")
        let output = hub.handle(.other(path: "globalmute", value: .number(0)), now: 0.2)
        _ = driver.take(output, hub: &hub, now: 0.2)
        // Mute Master off: the marks, still, alternate with the level (Adam, 2026-11-05).
        let off = driver.tick(hub: &hub, now: 0.6)
        XCTAssertEqual(off.midi.rings[1]?.amount, Self.half, "the level, half")
        XCTAssertEqual(off.midi.rings[1]?.b, 127, "in the channel's white")
        XCTAssertNil(off.midi.leds[1], "no marks in this half of the blink")
        let back = driver.tick(hub: &hub, now: 1.1)
        XCTAssertEqual(back.midi.leds[1]?.map(\.led), [0, 4, 8, 12], "the marks again, in place")
        XCTAssertNil(driver.tick(hub: &hub, now: 1.3).midi.rings[1], "still: a rotation step sends nothing")
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 2)
        let clear = driver.receive([0x80, 1, 0x00], hub: &hub, now: 2.1)
        XCTAssertEqual(clear.midi.lastTitle, "Vox MUTE CLR")
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 3)
        XCTAssertEqual(driver.receive([0x80, 1, 0x00], hub: &hub, now: 3.1).midi.lastTitle, "Vox MUTE SET")
    }

    func testTheShiftPagesDimAndMaximumIgnoreBrightness() {
        var hub = loadedHub()
        var driver = E16Driver(name: "e16")
        driver.brightness = 0.5
        driver.drawsScreen = false
        _ = driver.start(hub: &hub, now: 0)
        _ = driver.receive(ack, hub: &hub, now: 0)
        let shift = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(shift.midi.rings[0]?.g, 64, "in use: at the brightness (127 × 0.5)")
        XCTAssertEqual(shift.midi.rings[1]?.r, 2, "available: 2, whatever the brightness")
        let down = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 1.1)
        XCTAssertEqual(down.midi.rings[1]?.r, 127, "pressed: 127, whatever the brightness")
    }

    func testTheHostDrawnScreen() {
        var hub = loadedHub()
        var driver = E16Driver(name: "e16")
        _ = driver.start(hub: &hub, now: 0)
        let answer = driver.receive(ack, hub: &hub, now: 0)
        let frames = answer.midi.sysExMessages.filter { $0.starts(with: [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x02]) }
        XCTAssertEqual(frames.count, 1, "one FRAMEBUFFER, no LABELS")
        XCTAssertNil(answer.midi.lastTitle)
        XCTAssertEqual(frames[0].count, 8 + 1171 + 1)
        // The screen itself: the title at the left, its tail at the right, labels fitted by width.
        let screen = E16Driver.screen(title: "LEVEL", tail: "PFL 2/3", labels: ["ADT3", "P11/12", "", "", "", "", "", "", "", "", "", "", "A", "B", "C", "D"])
        let art = screen.art.split(separator: "\n")
        XCTAssertTrue(art[10].allSatisfy { $0 == "#" }, "the rule under the title")
        XCTAssertTrue(art[6].hasPrefix("...###."), "the title 3 px in, where the labels start (L's foot)")
        XCTAssertTrue(art[0].hasSuffix("###...."), "the tail ends 3 px from the right edge (the 3, 4 wide, its top row 3 wide)")
        XCTAssertTrue(art[14].hasPrefix("....###."), "the first label (ADT3) at the same 3 px (A's top)")
        XCTAssertTrue(art[14].dropFirst(32).hasPrefix("...####"), "the second column's label 3 px into its cell (P's top)")
        XCTAssertFalse(art[7].contains("#") || art[8].contains("#") || art[9].contains("#") || art[11].contains("#") || art[12].contains("#") || art[13].contains("#"), "three clear lines above and below the rule")
        XCTAssertTrue(art[20].contains("#") && !art[21].contains("#"), "the first row is 7 pixels tall")
        XCTAssertTrue(!art[55].contains("#") && art[56].contains("#") && art[62].contains("#"), "the fourth row at 56, 14 pixels per row")
        XCTAssertTrue(E16Driver.screen(title: "LEVEL", labels: []).art.split(separator: "\n")[0].hasSuffix("........"), "no tail")
        XCTAssertEqual(E16Driver.ShiftButton.output(1).longLabel, "SEND>")
    }

    func testBrightnessScalesEveryColorSent() {
        var hub = loadedHub()
        var driver = E16Driver(name: "e16")
        driver.brightness = 0.5
        _ = driver.start(hub: &hub, now: 0)
        let answer = driver.receive(ack, hub: &hub, now: 0)
        XCTAssertEqual(answer.midi.rings[0]?.r, 64, "Keys, red, at half")
        XCTAssertEqual(answer.midi.rings[1]?.g, 64, "Vox, white, at half")
        XCTAssertEqual(answer.midi.rings[0]?.amount, Self.half, "the fill is the level, not dimmed")
        driver.brightness = 0.001
        XCTAssertEqual(driver.take(hub.handle(.channel(bus: .input, channel: 2, parameter: "color", value: .number(4)), now: 3), hub: &hub, now: 3).midi.rings[1]?.r, 4, "a color's largest part never goes below the floor")
        // Dimming keeps the proportions, so orange stays orange and apart from red at the lowest
        // setting (Adam, 2026-11-04).
        driver.brightness = 0.1
        let orange = driver.take(hub.handle(.channel(bus: .input, channel: 2, parameter: "color", value: .number(3)), now: 4), hub: &hub, now: 4).midi.rings[1]
        XCTAssertEqual(orange?.r, 13)
        XCTAssertEqual(orange?.g, 3)
        XCTAssertEqual(E16Driver.scaled((127, 25, 0), brightness: 0.01).0, 4, "held at the floor, in proportion")
        XCTAssertEqual(E16Driver.scaled((127, 25, 0), brightness: 0.01).1, 1, "a lit part never rounds to nothing")
    }

    /// Only the ACK connects: a turn or a push from a device still in its own scene must not
    /// (review of 2026-11-04), and ENTER is asked again meanwhile.
    func testOnlyTheACKConnects() {
        var hub = loadedHub()
        var driver = E16Driver(name: "e16")
        _ = driver.start(hub: &hub, now: 0)
        let turn = driver.receive([0xB0, 1, 0x05, 0x90, 0, 0x7F, 0x80, 0, 0x00], hub: &hub, now: 0.5)
        XCTAssertFalse(driver.isConnected)
        XCTAssertEqual(turn.core.messages, [], "nothing sent to TotalMix FX from a device not in Remote Mode")
        XCTAssertEqual(turn.midi, [])
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.1).midi, E16Outgoing.enterRemoteMode, "ENTER asked again")
        _ = driver.receive(ack, hub: &hub, now: 1.2)
        XCTAssertTrue(driver.isConnected)
    }

    /// The screen is drawn and packed only when something on it changed: a tick with nothing
    /// new sends nothing (review of 2026-11-04: every tick rendered a framebuffer).
    func testTheScreenIsNotRedrawnWhenNothingChanged() {
        var hub = loadedHub()
        var driver = E16Driver(name: "e16")
        _ = driver.start(hub: &hub, now: 0)
        let first = driver.receive(ack, hub: &hub, now: 0)
        XCTAssertTrue(first.midi.count > 1024, "the first screen")
        XCTAssertEqual(driver.take(CoreOutput(), hub: &hub, now: 0.01).midi, [])
        XCTAssertEqual(driver.tick(hub: &hub, now: 0.02).midi, [])
    }

    func testLabelsKeepTheFirstNumber() {
        XCTAssertEqual(E16Driver.fit("PB 11/12", 4), "11/1", "a pair never loses its second number; four characters can't hold this one")
        XCTAssertEqual(E16Driver.fit("PB 1/2", 4), "P1/2")
        XCTAssertEqual(E16Driver.fit("ADAT 3/4", 4), "A3/4")
        XCTAssertEqual(E16Driver.fit("ADAT 11/12", 4), "11/1")
        XCTAssertEqual(E16Driver.fit("Mic 1/2", 4), "M1/2")
        XCTAssertEqual(E16Driver.fit("Analog 1/2", 4), "A1/2")
        XCTAssertEqual(E16Driver.fit("Tonverk", 4), "Tonv")
        XCTAssertEqual(E16Driver.fit("ADI-2", 4), "ADI2")
        XCTAssertEqual(E16Driver.fit("Mic 1/2", 8), "Mic 1/2")
        XCTAssertEqual(E16Driver.fit("ADAT 3/4", 6), "ADT3/4", "the pair, with the vowels gone")
        XCTAssertEqual(E16Driver.fit("PB 11/12", 6), "P11/12")
        XCTAssertEqual(E16Driver.fit("ADAT 3/4", 7), "ADAT3/4", "the pair, without its space")
        XCTAssertEqual(E16Driver.fit("PB 11/12", 7), "PB11/12")
        XCTAssertEqual(E16Driver.fit("ADAT 11/12", 6), "AD11/12".count > 6 ? "A11/12" : "", "letters go before the pair does")
        XCTAssertEqual(E16Driver.fit("Analog 1/2", 6), "Anlg1/2".count > 6 ? "Anl1/2" : "")
        XCTAssertEqual(E16Driver.fit("Analog 1", 6), "Anlg 1", "a single number keeps the space while it can")
        XCTAssertEqual(E16Driver.fit("Tonverk", 6), "Tonver")
        // By pixel width, for the host-drawn screen (26 px: a 32 px cell, 6 px between neighbors).
        let w = E16Driver.labelMaxWidth
        XCTAssertEqual(E16Driver.fit("PB 11/12", width: w), "P11/12", "narrow 1s and / let the pair fit")
        XCTAssertEqual(E16Driver.fit("PB 15/16", width: w), "P15/16")
        XCTAssertEqual(E16Driver.fit("PB 15/16", 5), "15/16", "the pair alone")
        XCTAssertEqual(E16Driver.fit("PB 1/2", width: w), "PB1/2")
        XCTAssertEqual(E16Driver.fit("ADAT 3/4", width: w), "AD3/4")
        XCTAssertEqual(E16Driver.fit("ADAT 11/12", width: w), "A11/12")
        XCTAssertEqual(E16Driver.fit("Mic 1/2", width: w), "Mc1/2")
        XCTAssertEqual(E16Driver.fit("Tonverk", width: w), "Tonv")
        XCTAssertEqual(E16Driver.fit("ADI-2", width: w), "ADI-2", "fits as it is")
        XCTAssertEqual(E16Driver.fit("AES 100/101", width: w), "100/10", "a three-digit pair: cut rather than blank (review of 2026-11-04)")
        XCTAssertLessThanOrEqual(E16Screen.width(of: "P11/12"), w)
    }

}
