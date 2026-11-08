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
        XCTAssertEqual(squeezed(step.midi.lastTitle), "Vox " + ValueText.level(position: position))
        // The title goes back to the function after a second.
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.5).midi, [])
        XCTAssertNil(driver.tick(hub: &hub, now: 1.5).midi.lastTitle)
        XCTAssertEqual(driver.tick(hub: &hub, now: 2.1).midi.lastTitle, "LEVEL")
        // Counter-clockwise, to the bottom and no further.
        let down = driver.receive([0xB0, 2, 0x78], hub: &hub, now: 3)  // −8
        XCTAssertEqual(down.core.messages.first?.arguments.first, .float(Float(position - 8 * E16Driver.levelStep)))
        for _ in 0..<40 { _ = driver.receive([0xB0, 2, 0x78], hub: &hub, now: 3) }
        let bottom = driver.receive([0xB0, 2, 0x78], hub: &hub, now: 4)
        XCTAssertTrue(bottom.core.messages.isEmpty, "at the bottom already: nothing more is sent (review, 2026-11-07)")
        XCTAssertEqual(squeezed(driver.title(hub: hub)), "Vox -oo dB")
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

    /// Push-and-turn jumps to the next stop the way it turns, after `jumpUnits` one way, and
    /// cancels the push: no mute on release, no PFL however long it is held (test 6; Adam,
    /// 2026-11-05 and 2026-11-06).
    func testPushAndTurnJumpsAndCancelsThePush() {
        var (driver, hub, _) = connected()
        let unity = Float(FaderCurve.unityPosition)
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 1)  // push Vox
        XCTAssertEqual(driver.receive([0xB0, 2, 0x01], hub: &hub, now: 1.1).core.messages, [], "one unit: no jump")
        XCTAssertEqual(driver.receive([0xB0, 2, 0x7F], hub: &hub, now: 1.15).core.messages, [], "a unit back starts again")
        _ = driver.receive([0xB0, 2, 0x01], hub: &hub, now: 1.2)
        let up = driver.receive([0xB0, 2, 0x01], hub: &hub, now: 1.25)
        XCTAssertEqual(up.core.messages.map(\.address), ["/mix/in/2/0/faderlin"], "the level, in LEVEL mode")
        XCTAssertEqual(up.core.messages.first?.arguments.first, .float(unity), "to 0 dB")
        XCTAssertTrue(driver.title(hub: hub).hasPrefix("Vox "), "and the title its value")
        XCTAssertEqual(driver.receive([0xB0, 2, 0x02], hub: &hub, now: 1.3).core.messages, [], "held at 0 dB by the pause")
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.5).midi, [], "no countdown")
        let late = driver.tick(hub: &hub, now: 2.2)
        XCTAssertFalse(late.core.messages.contains { $0.address.hasSuffix("/pfl") }, "no PFL after a second")
        let down = driver.receive([0xB0, 2, 0x7E], hub: &hub, now: 2.25)  // two units down at once
        XCTAssertEqual(down.core.messages.first?.arguments.first, .float(0), "to off")
        let release = driver.receive([0x80, 1, 0x00], hub: &hub, now: 2.3)
        XCTAssertEqual(release.core.messages, [], "no mute on release")
        // A plain turn is a plain turn again.
        XCTAssertEqual(driver.receive([0xB0, 2, 0x01], hub: &hub, now: 2.5).core.messages.first?.arguments.first,
                       .float(Float(E16Driver.levelStep)))
        // A turn after the countdown has begun cancels it.
        _ = driver.receive([0x90, 2, 0x7F], hub: &hub, now: 3)  // push Gtr
        _ = driver.tick(hub: &hub, now: 3.4)
        XCTAssertEqual(driver.title(hub: hub), "Gtr -> PFL")
        _ = driver.receive([0xB0, 3, 0x01], hub: &hub, now: 3.5)
        XCTAssertFalse(driver.title(hub: hub).contains("PFL"))
        XCTAssertEqual(driver.receive([0x80, 2, 0x00], hub: &hub, now: 4.5).core.messages, [])
        // In PAN mode, it jumps the pan: center, then hard right.
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 1, 0x7F, 0x80, 1, 0x00, 0x90, 16, 0x00], hub: &hub, now: 5)  // Shift + 2
        XCTAssertEqual(driver.function, .pan)
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 6)
        let right = driver.receive([0xB0, 2, 0x02], hub: &hub, now: 6.1)
        XCTAssertEqual(right.core.messages.map(\.address), ["/mix/in/2/0/balpan"])
        XCTAssertEqual(right.core.messages.first?.arguments.first, .float(1), "hard right")
        let center = driver.receive([0xB0, 2, 0x7E], hub: &hub, now: 6.5)
        XCTAssertEqual(center.core.messages.first?.arguments.first, .float(0), "back to center")
        let left = driver.receive([0xB0, 2, 0x7E], hub: &hub, now: 6.9)
        XCTAssertEqual(left.core.messages.first?.arguments.first, .float(-1), "hard left")
    }

    /// Each stop is sticky: after a jump the turn must pause, as at a pan's center (Adam,
    /// 2026-11-06), so a fast turn from above 0 dB stops at 0 dB.
    func testJumpsPauseAtEachStop() {
        var (driver, hub, _) = connected()
        let pause = E16Driver.jumpPauseDefault
        _ = driver.receive([0xB0, 2, 0x3F, 0xB0, 2, 0x3F, 0xB0, 2, 0x3F], hub: &hub, now: 0.5)  // Vox above 0 dB
        _ = driver.receive([0x90, 1, 0x7F], hub: &hub, now: 1)
        let down = driver.receive([0xB0, 2, 0x7E], hub: &hub, now: 1.1)
        XCTAssertEqual(down.core.messages.first?.arguments.first, .float(Float(FaderCurve.unityPosition)), "to 0 dB first")
        var t = 1.1
        for _ in 0..<100 {  // a fast turn keeps coming, 5 ms apart, for longer than the pause
            t += 0.005
            XCTAssertEqual(driver.receive([0xB0, 2, 0x7E], hub: &hub, now: t).core.messages, [], "held at 0 dB")
        }
        let on = driver.receive([0xB0, 2, 0x7E], hub: &hub, now: t + pause + 0.01)
        XCTAssertEqual(on.core.messages.first?.arguments.first, .float(0), "after a pause, on to off")
    }

    func testJumpStops() {
        let unity = FaderCurve.unityPosition
        let stops = E16Driver.jumpStops(pan: false)
        XCTAssertEqual(E16Driver.nextStop(from: 0.3, direction: 1, stops: stops, tolerance: 0.001), unity)
        XCTAssertEqual(E16Driver.nextStop(from: 0.3, direction: -1, stops: stops, tolerance: 0.001), 0)
        XCTAssertEqual(E16Driver.nextStop(from: 0.95, direction: -1, stops: stops, tolerance: 0.001), unity, "above 0 dB: down to 0 dB first")
        XCTAssertEqual(E16Driver.nextStop(from: 0.95, direction: 1, stops: stops, tolerance: 0.001), 1, "up to +6 dB")
        XCTAssertEqual(E16Driver.nextStop(from: unity + 0.0005, direction: 1, stops: stops, tolerance: 0.001), 1, "at 0 dB, within the tolerance: on to +6 dB")
        XCTAssertNil(E16Driver.nextStop(from: 1, direction: 1, stops: stops, tolerance: 0.001), "nothing past the top")
        XCTAssertNil(E16Driver.nextStop(from: 0, direction: -1, stops: stops, tolerance: 0.001))
        let pans = E16Driver.jumpStops(pan: true)
        XCTAssertEqual(E16Driver.nextStop(from: 0.2, direction: 1, stops: pans, tolerance: 0.001), 0.5)
        XCTAssertEqual(E16Driver.nextStop(from: 0.5, direction: 1, stops: pans, tolerance: 0.001), 1)
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
                                               "Phon", "", "", "", "16CH", "STRP", "", ""],
                       "one page: no page arrows; one send output: no send arrows, in any mode")
        let rings = shift.midi.rings
        XCTAssertEqual(rings[0]?.g, 127, "LEVEL, in use: white at the driver's brightness (1 in the tests)")
        XCTAssertEqual(rings[0]?.amount, 16383)
        XCTAssertEqual(rings[1]?.r, 2, "PAN: magenta at the available level")
        XCTAssertEqual(rings[1]?.b, 2)
        XCTAssertEqual(rings[1]?.amount, 16383)
        XCTAssertEqual(rings[2]?.g, 2, "SEND: green at the available level")
        XCTAssertNil(rings[10], "the arrows step from the output named beside them, in every mode: none before Phones")
        XCTAssertNil(rings[11], "nor after it")
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
        // SEND: the only send, Phones.
        let out = driver.receive([0x90, 2, 0x7F, 0x80, 2, 0x00], hub: &hub, now: 1.3)
        XCTAssertEqual(driver.function, .send(0))
        XCTAssertEqual(out.midi.lastTitle, "> PHONES")
        XCTAssertEqual(out.midi.rings[2]?.g, 60, "SEND in use")
        XCTAssertNil(out.midi.rings[11], "no next output: the arrow stays dark")
        XCTAssertNil(out.midi.rings[10], "no previous output either")
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
        let step = driver.receive([0xB0, 1, UInt8(E16Driver.panCenterUnits + 2)], hub: &hub, now: 2)  // leaves center: one step
        XCTAssertEqual(step.core.messages.map(\.address), ["/mix/in/0/0/balpan"])
        XCTAssertEqual(step.core.messages.first?.arguments.first, .float(Float(2 * E16Driver.panStep)))  // R1, on TotalMix FX's −1…1
        XCTAssertEqual(squeezed(step.midi.lastTitle), "Keys R1")
        XCTAssertEqual(step.midi.rings[0]?.bipolar, true)
    }

    /// The layout and meters set from the app (phase 2): a connected device switches as with its
    /// Shift page's buttons; one not yet connected has its layers swapped in the hub.
    func testLayoutAndMetersFromTheApp() {
        var (driver, hub, _) = connected()
        let step = driver.setLayout(.four, hub: &hub, now: 5)
        XCTAssertEqual(driver.layout, .four)
        XCTAssertFalse(step.midi.isEmpty, "a connected device is drawn afresh")
        XCTAssertNotNil(hub.mode(of: driver.id(.sendA)))
        XCTAssertNil(hub.mode(of: driver.id(.main)))
        XCTAssertTrue(driver.setLayout(.four, hub: &hub, now: 6).midi.isEmpty, "the layout in use: nothing")
        XCTAssertFalse(driver.showsMeters)
        _ = driver.setShowsMeters(true, hub: hub)
        XCTAssertTrue(driver.showsMeters)
        XCTAssertTrue(driver.setShowsMeters(true, hub: hub).isEmpty, "no change, nothing sent")

        var waiting = SurfaceHub()
        var other = E16Driver(name: "e16")
        _ = other.start(hub: &waiting, now: 0)
        XCTAssertTrue(other.setLayout(.four, hub: &waiting, now: 1).midi.isEmpty, "nothing to draw until the device answers")
        XCTAssertEqual(other.layout, .four)
        XCTAssertNotNil(waiting.mode(of: other.id(.level)))
        XCTAssertNil(waiting.mode(of: other.id(.main)))
    }

    func testPanCenterIsSticky() {
        var (driver, hub, _) = connected()
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 1, 0x7F, 0x80, 1, 0x00, 0x90, 16, 0x00], hub: &hub, now: 1)  // PAN
        let units = E16Driver.panCenterUnits
        var clock = 2.0
        /// A turn on encoder `encoder` (from 1); `gap` seconds after the last one.
        func turn(_ delta: Int, encoder: UInt8 = 1, gap: Double = 1) -> String {
            clock += gap
            _ = driver.receive([0xB0, encoder, UInt8(delta < 0 ? 128 + delta : delta)], hub: &hub, now: clock)
            return driver.title(hub: hub)
        }
        XCTAssertEqual(squeezed(turn(units)), "Keys C", "held at center for \(units) units")
        XCTAssertEqual(squeezed(turn(1)), "Keys R1", "the next unit moves it")
        XCTAssertEqual(squeezed(turn(-8)), "Keys C", "a fast turn back stops at center")
        XCTAssertEqual(squeezed(turn(-(units - 1))), "Keys C")
        XCTAssertEqual(squeezed(turn(2)), "Keys C", "a turn the other way starts the count again")
        XCTAssertEqual(squeezed(turn(units - 1)), "Keys R1", "\(units + 1) units that way, in all")
        XCTAssertEqual(squeezed(turn(8)), "Keys R9")
        XCTAssertEqual(squeezed(turn(-20)), "Keys C", "crossing from the right stops at center too")
        XCTAssertEqual(squeezed(turn(-(units + 3))), "Keys L1", "the units beyond the count don't carry: one step")
        XCTAssertEqual(squeezed(turn(-2)), "Keys L3", "away from center, every unit counts")
        // A fast turn is a burst of messages: the rest of the burst is ignored at center, and
        // the count starts only after a pause (Adam, 14:56: a fast turn went straight through).
        _ = turn(-22)
        XCTAssertEqual(squeezed(driver.title(hub: hub)), "Keys L25")
        for _ in 0..<10 { _ = turn(8, gap: 0.02) }
        XCTAssertEqual(squeezed(driver.title(hub: hub)), "Keys C", "a burst from L25 stops at center")
        XCTAssertEqual(squeezed(turn(8, gap: driver.panCenterPause - 0.01)), "Keys C", "still the same turn")
        XCTAssertEqual(squeezed(turn(units + 1, gap: driver.panCenterPause + 0.01)), "Keys R1", "after a pause, the count")
        // Amounts side by side, for trying them: encoder 2 (index 1) takes the second.
        driver.panCenterTrial = [0, 8]
        XCTAssertEqual(squeezed(turn(-8)), "Keys C", "crossing still stops at center")
        XCTAssertEqual(squeezed(turn(-2)), "Keys L1", "encoder 1 takes 0: no units held, and one step")
        XCTAssertTrue(turn(8, encoder: 2).hasSuffix(" C"), "encoder 2 held for 8 units")
        XCTAssertTrue(turn(1, encoder: 2).hasSuffix(" R1"))
        // How a pan leaves center, side by side: encoder 2 carries the units beyond the count.
        driver.panCenterTrial = []
        driver.panLeaveTrial = [true, false]
        _ = turn(-8, encoder: 2)
        XCTAssertTrue(turn(units + 3, encoder: 2).hasSuffix(" R3"), "carried: 3 units past the count")
        XCTAssertEqual(squeezed(turn(8)), "Keys C", "from L1, back to center")
        XCTAssertEqual(squeezed(turn(units + 3)), "Keys R1", "encoder 1: one step")
        // A level has no sticky point.
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 0, 0x7F, 0x80, 0, 0x00, 0x90, 16, 0x00], hub: &hub, now: clock + 1)  // LEVEL
        let level = driver.receive([0xB0, 1, 0x01], hub: &hub, now: clock + 1.1)
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
        XCTAssertEqual(clear.midi.lastTitle, "Vox MUTE OFF", "off is off, whatever Mute Master says")
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
        // The button in use never below `inUseFloor` (Adam, 2026-11-07), and it follows the setting.
        _ = driver.receive([0x80, 1, 0x00, 0x80, 16, 0x00], hub: &hub, now: 1.2)
        _ = driver.setBrightness(0.03, hub: hub)
        let low = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 1.3)
        XCTAssertEqual(low.midi.rings[1]?.r, UInt8(E16Driver.inUseFloorDefault), "PAN, now in use, at 3%: the floor, not 4")
        // It pulses down to the available level and back, a period after Shift went down.
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.3 + E16Driver.pulsePeriodDefault / 2).midi.rings[1]?.r, UInt8(2 + E16Driver.pulseTroughRaiseDefault), "half a pulse: the trough, the available 2")
        XCTAssertEqual(driver.tick(hub: &hub, now: 1.3 + E16Driver.pulsePeriodDefault).midi.rings[1]?.r, UInt8(E16Driver.inUseFloorDefault), "a whole pulse: bright again")
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
        XCTAssertTrue(!art[52].contains("#") && art[53].contains("#") && art[59].contains("#"), "the fourth row at 53, 13 pixels per row")
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

/// The 4-channel layout (Adam, 2026-11-05): `loadedHub()` with two more outputs, 4/5 ("Mon",
/// blue) and 6/7 ("Room"), so the send targets are outputs 3/4, 5/6… as indices: Phones (2), Mon
/// (4), and Room (6).
private func fourHub() -> SurfaceHub {
    var hub = loadedHub()
    var events: [TotalMixEvent] = []
    for (number, name, color) in [(4, "Mon", 5), (6, "Room", 1)] {
        events.append(.channel(bus: .output, channel: number, parameter: "stereo", value: .number(1)))
        events.append(.channel(bus: .output, channel: number, parameter: "name", value: .text(name)))
        events.append(.channel(bus: .output, channel: number, parameter: "color", value: .number(Double(color))))
        events.append(.channel(bus: .output, channel: number, parameter: "faderlin", value: .number(0.6)))
        for (bus, channel) in [(TotalMixBus.input, 0), (.input, 2), (.input, 3), (.playback, 0)] {
            events.append(.mix(bus: bus, channel: channel, output: number, parameter: "faderlin", value: .number(0.5)))
        }
    }
    for event in events { _ = hub.handle(event, now: 0) }
    return hub
}

private func connectedFour() -> (driver: E16Driver, hub: SurfaceHub, midi: [UInt8]) {
    var hub = fourHub()
    var driver = E16Driver(name: "e16", layout: .four)
    driver.brightness = 1
    driver.drawsScreen = false
    let start = driver.start(hub: &hub, now: 0)
    let answer = driver.receive(ack, hub: &hub, now: 0)
    return (driver, hub, start.midi + answer.midi)
}

final class E16FourLayoutTests: XCTestCase {
    /// Encoder 13 on the Shift page switches layouts (Adam, 2026-11-06): to 4 channel strips at
    /// the row holding the channel last turned, and back at the page holding the four.
    /// A press that reaches the last page keeps its flash until release (Adam, 2026-11-06).
    func testAnArrowReachingTheEndFlashesUntilRelease() {
        var hub = fourHub()
        for n in 4..<8 {
            for (parameter, value) in [("stereo", TotalMixValue.number(0)), ("name", .text("In\(n)")), ("color", .number(1))] {
                _ = hub.handle(.channel(bus: .input, channel: n, parameter: parameter, value: value), now: 0)
            }
        }
        var driver = E16Driver(name: "e16", layout: .four)
        driver.brightness = 1
        _ = driver.start(hub: &hub, now: 0)
        _ = driver.receive(ack, hub: &hub, now: 0)
        _ = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 1)
        let down = driver.receive([0x90, 15, 0x7F], hub: &hub, now: 2)  // to the last page
        XCTAssertEqual(down.midi.rings[15].map { [$0.r, $0.g, $0.b] }, [0, 0, 127], "the flash")
        let up = driver.receive([0x80, 15, 0x00], hub: &hub, now: 2.2)
        XCTAssertEqual(up.midi.rings[15]?.amount, 0, "then dark: nowhere further")
        let again = driver.receive([0x90, 15, 0x7F], hub: &hub, now: 3)
        XCTAssertNil(again.midi.rings[15], "an unavailable arrow stays dark when pressed")
    }

    func testLayoutSwitch() {
        XCTAssertEqual(E16Driver.shiftSpans(.four), [0, 4], "the send names left-aligned")
        XCTAssertEqual(E16Driver.shiftSpans(.sixteen), [8], "the layout labels centered, like the modes")
        var hub = loadedHub()
        for n in 4..<10 {
            for (parameter, value) in [("stereo", TotalMixValue.number(0)), ("name", .text("In\(n)")), ("color", .number(1))] {
                _ = hub.handle(.channel(bus: .input, channel: n, parameter: parameter, value: value), now: 0)
            }
        }
        var driver = E16Driver(name: "e16")
        driver.brightness = 1
        driver.drawsScreen = false
        _ = driver.start(hub: &hub, now: 0)
        let first = driver.receive(ack, hub: &hub, now: 0).midi.lastLabels ?? []
        XCTAssertEqual(first.count, 16)
        _ = driver.receive([0xB0, 6, 0x01], hub: &hub, now: 1)  // turn the seventh channel
        let shift = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 2)
        XCTAssertEqual(shift.midi.lastLabels.map { Array($0[12...13]) }, ["16CH", "STRP"], "a button for each layout")
        XCTAssertEqual(shift.midi.rings[12].map { [$0.r, $0.g, $0.b] }, [127, 85, 0], "the layout in use, lit in full")
        XCTAssertEqual(shift.midi.rings[13].map { [$0.r, $0.g, $0.b] }, [3, 2, 0], "the other, dim, and still yellow (2, 1, 0 read as orange)")
        XCTAssertEqual(driver.receive([0x90, 12, 0x7F, 0x80, 12, 0x00], hub: &hub, now: 2.05).core.messages, [])
        XCTAssertEqual(driver.layout, .sixteen, "the layout in use: nothing")
        let press = driver.receive([0x90, 13, 0x7F], hub: &hub, now: 2.1)
        XCTAssertEqual(driver.layout, .four)
        XCTAssertEqual(press.midi.rings[13].map { [$0.r, $0.g, $0.b] }, [127, 85, 0], "Shift still held: now 4 lit")
        _ = driver.receive([0x80, 13, 0x00], hub: &hub, now: 2.2)
        let four = driver.receive([0x80, 16, 0x00], hub: &hub, now: 2.3).midi.lastLabels ?? []
        XCTAssertEqual(Array(four[12..<16]), Array(first[4..<8]), "the row holding the channel turned")
        XCTAssertFalse(driver.receive([0xB0, 13, 0x01], hub: &hub, now: 3).core.messages.isEmpty, "a level turns")
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 12, 0x7F, 0x80, 12, 0x00], hub: &hub, now: 4)
        XCTAssertEqual(driver.layout, .sixteen)
        let back = driver.receive([0x80, 16, 0x00], hub: &hub, now: 4.1).midi.lastLabels ?? []
        XCTAssertEqual(Array(back[0..<8]), Array(first[0..<8]), "the page holding the four")
    }

    func testColumnsAndRows() {
        let (driver, hub, midi) = connectedFour()
        XCTAssertEqual(hub.sendTargets, [2, 4, 6])
        XCTAssertEqual(driver.currentSendOutputs(hub: hub), [2, 4], "A and B take the first two outputs")
        XCTAssertEqual(midi.lastTitle, "A>PHO B>MON")
        let labels = midi.lastLabels ?? []
        let half = E16Driver.shortLevel(0.5, width: nil)
        XCTAssertEqual(Array(labels[0..<8]), Array(repeating: half, count: 8), "send A's and B's levels")
        XCTAssertEqual(Array(labels[8..<12]), ["", "", "", ""], "centered pans show nothing")
        XCTAssertEqual(Array(labels[12..<16]), ["Keys", "Vox", "Gtr", "P1/2"], "the names, once, at the bottom")
        let rings = midi.rings
        XCTAssertEqual(rings[12]?.r, 127, "level: Keys is red")
        XCTAssertEqual(rings[12]?.amount, E16DriverTests.half)
        XCTAssertEqual(rings[8]?.bipolar, true, "pan")
        XCTAssertEqual(rings[8]?.amount, 8192, "centered")
        XCTAssertEqual(rings[0]?.r, 127, "send A to a white output: the channel's color")
        XCTAssertEqual(rings[0]?.amount, E16DriverTests.half)
        XCTAssertEqual(rings[4]?.b, 127, "send B to a blue output: its color")
        XCTAssertEqual(rings[4]?.r, 0)
    }

    func testTitleGivesSendNamesTheRoomItHas() {
        var (driver, hub, _) = connectedFour()
        driver.drawsScreen = true
        let name = driver.functionName(hub: hub)
        XCTAssertTrue(name.hasPrefix("A>") && name.contains("\tB>MON"), name)
        XCTAssertGreaterThan(name.count, "A>PHO\tB>MON".count, "more than three characters each where they fit: \(name)")
        let parts = name.split(separator: "\t").map(String.init)
        let margin = (E16Screen.width / 4 - E16Driver.labelMaxWidth) / 2
        let screen = E16Driver.screen(title: name, tail: "■ 10/12", labels: [])
        let bEnd = E16Screen.width * 3 / 4 - margin - 1
        XCTAssertTrue((0..<7).contains { screen.pixel(bEnd, $0) } || (0..<7).contains { screen.pixel(bEnd - 1, $0) }, "send B ends at the third column's margin")
        XCTAssertLessThan(margin + E16Screen.width(of: parts[0]) + 4, bEnd - E16Screen.width(of: parts[1]), "a clear gap between the names")
        XCTAssertFalse(driver.title(hub: hub).isEmpty)
        _ = hub
    }

    func testTitleShowsPFLOnlyWhenItIsOffThePage() {
        var (driver, hub, _) = connectedFour()
        driver.drawsScreen = true
        _ = hub.handle(.channel(bus: .input, channel: 2, parameter: "pfl", value: .number(1)), now: 1)
        XCTAssertFalse(driver.titleParts(hub: hub).1.contains("■"), "Vox is on this page: its name shows the square")
        driver.marksNames = false
        XCTAssertTrue(driver.titleParts(hub: hub).1.contains("■"), "without name marks, the title shows it")
        driver.marksNames = true
        _ = hub.handle(.channel(bus: .input, channel: 2, parameter: "pfl", value: .number(0)), now: 2)
        _ = hub.handle(.channel(bus: .input, channel: 30, parameter: "pfl", value: .number(1)), now: 2)
        XCTAssertTrue(driver.titleParts(hub: hub).1.contains("■"), "a PFL off the page shows in the title")
        driver.drawsScreen = false
        XCTAssertTrue(driver.titleParts(hub: hub).1.contains("PFL"), "the firmware's labels say PFL")
    }

    func testStripsShowOnlyTheMainLevelInTheTitle() {
        var (driver, hub, _) = connectedFour()
        driver.drawsScreen = true
        let before = driver.title(hub: hub)
        _ = driver.receive([0xB0, 1, 0x04], hub: &hub, now: 1)  // Keys's send A
        XCTAssertEqual(driver.title(hub: hub), before, "a send's value shows in its own cell, not again in the title")
        _ = driver.receive([0xB0, 9, 0x04], hub: &hub, now: 1.5)  // Keys's pan
        XCTAssertEqual(driver.title(hub: hub), before, "nor a pan's")
        _ = driver.receive([0xB0, 13, 0x04], hub: &hub, now: 2)  // Keys's level
        let title = driver.title(hub: hub)
        XCTAssertTrue(title.uppercased().hasPrefix("KEYS "), title)
        XCTAssertFalse(title.contains(">"), "a level turn names only the channel")
    }

    func testEachRowTurnsItsOwnControl() {
        var (driver, hub, _) = connectedFour()
        XCTAssertEqual(driver.receive([0xB0, 1, 0x04], hub: &hub, now: 1).core.messages.map(\.address), ["/mix/in/0/2/faderlin"], "row 1: send A")
        XCTAssertEqual(driver.receive([0xB0, 6, 0x04], hub: &hub, now: 2).core.messages.map(\.address), ["/mix/in/2/4/faderlin"], "row 2: send B")
        XCTAssertEqual(driver.receive([0xB0, 11, 0x04], hub: &hub, now: 3).core.messages.first?.address.hasSuffix("balpan"), true, "row 3: pan")
        XCTAssertEqual(driver.receive([0xB0, 16, 0x04], hub: &hub, now: 4).core.messages.map(\.address), ["/mix/pb/0/0/faderlin"], "row 4: level")
    }

    func testMuteFromAnyRowShowsOnTheLevelRingAndDarkensTheSends() {
        var (driver, hub, _) = connectedFour()
        let step = driver.receive([0x90, 5, 0x7F, 0x80, 5, 0x00], hub: &hub, now: 1)  // row 2, Vox
        XCTAssertEqual(step.core.messages.map(\.address), ["/input/2/mute"])
        let midi = step.midi + driver.tick(hub: &hub, now: 1.2).midi
        XCTAssertEqual(midi.rings[13]?.amount, 0, "the level ring shows the marks")
        XCTAssertEqual(midi.leds[13]?.count, 4)
        XCTAssertEqual(midi.leds[13]?.first?.g, E16Driver.muteRGB.1, "orange")
        XCTAssertEqual(midi.rings[1]?.amount, 0, "send A dark")
        XCTAssertEqual(midi.rings[5]?.amount, 0, "send B dark")
        XCTAssertNil(midi.rings[9], "the pan unchanged: nothing sent")
    }

    func testNameMarks() {
        let labels = Array(repeating: "", count: 12) + ["Vox", "", "", ""]
        let plain = E16Driver.screen(title: "", labels: labels)
        let marked = E16Driver.screen(title: "", labels: labels, inverted: [12], pflMarked: [12])
        let margin = (E16Screen.width / 4 - E16Driver.labelMaxWidth) / 2, y = E16Driver.labelTop + 3 * E16Driver.labelPitch
        XCTAssertFalse(plain.pixel(margin - 1, y - 1))
        XCTAssertTrue(marked.pixel(margin - 1, y - 1), "the box around the name")
        XCTAssertNotEqual(plain.pixel(margin, y), marked.pixel(margin, y), "the letters flipped")
        let empty = E16Driver.screen(title: "", labels: Array(repeating: "", count: 16), inverted: [12])
        XCTAssertFalse(empty.pixel(margin - 1, y - 1), "no box without a name")
        let pfl = E16Driver.screen(title: "", labels: labels, pflMarked: [12])
        let after = margin + E16Screen.width(of: "Vox") + 2
        XCTAssertTrue(pfl.pixel(after, y + 2) && pfl.pixel(after + 2, y + 4), "a 3 x 3 square after the name")
        XCTAssertFalse(pfl.pixel(after - 1, y + 3) || pfl.pixel(after + 3, y + 3) || pfl.pixel(after + 1, y + 1))
        XCTAssertFalse((0..<E16Screen.width).contains { pfl.pixel($0, y + E16Font.glyphHeight + 1) }, "no underline")
        let both = E16Driver.screen(title: "", labels: labels, inverted: [12], pflMarked: [12])
        XCTAssertTrue(both.pixel(after + 3, y - 1), "the box takes in the square")
        XCTAssertFalse(both.pixel(after + 1, y + 3), "the square dark in the lit box")
    }

    func testMeters() {
        let labels = Array(repeating: "", count: 12) + ["Vox", "P1/2", "", ""]
        let screen = E16Driver.screen(title: "", labels: labels, centered: true, meters: [12: [13], 13: [26, 5]])
        let margin = (E16Screen.width / 4 - E16Driver.labelMaxWidth) / 2, y = E16Driver.labelTop + 3 * E16Driver.labelPitch
        let line = y + E16Driver.meterTop
        XCTAssertEqual(line, 62, "two blank lines under the name")
        XCTAssertTrue(screen.pixel(margin, line) && screen.pixel(margin + 12, line), "half a cell")
        XCTAssertFalse(screen.pixel(margin + 13, line))
        XCTAssertFalse(screen.pixel(margin, line - 1), "blank lines under the letters")
        XCTAssertTrue(screen.pixel(32 + margin + 25, line), "full")
        XCTAssertFalse(screen.pixel(32 + margin + 26, line))
        XCTAssertTrue(screen.pixel(32 + margin + 4, line + 1) && !screen.pixel(32 + margin + 5, line + 1), "a stereo channel's right side under its left")
        XCTAssertFalse(screen.pixel(margin, line + 1), "one line for a mono channel")
        let held = E16Driver.screen(title: "", labels: labels, meters: [12: [5]], peaks: [12: [20]])
        XCTAssertTrue(held.pixel(margin + 19, line) && !held.pixel(margin + 18, line) && !held.pixel(margin + 5, line), "one pixel at the peak")
    }

    func testBarAveragesThePeaks() {
        var (driver, hub, _) = connectedFour()
        driver.drawsScreen = true
        driver.showsMeters = true
        driver.meterAverage = 0.3
        _ = driver.tick(hub: &hub, now: 1)
        _ = hub.handle(.level(bus: .input, channel: 0, peakDB: -1), now: 1)
        XCTAssertFalse(driver.tick(hub: &hub, now: 1.05).midi.isEmpty, "redrawn as the bar rises")
        // After 0.05 s of a −1 dB peak from silence, the average is still well below it; after
        // 2 s, it has caught up. (The bar's width is internal; this checks the arithmetic.)
        let early = 1 - exp(-0.05 / 0.3), late = 1 - exp(-2.0 / 0.3)
        XCTAssertLessThan(10 * log10(early * pow(10, -0.1)), -8, "the bar rises slowly")
        XCTAssertGreaterThan(10 * log10(late * pow(10, -0.1)), -1.1, "and catches up")
    }

    func testPeakHoldsThenDrops() {
        var (driver, hub, _) = connectedFour()
        driver.drawsScreen = true
        driver.showsMeters = true
        driver.peakHold = 1
        func line(_ midi: [UInt8]) -> Bool { !midi.isEmpty }
        _ = hub.handle(.level(bus: .input, channel: 0, peakDB: -1), now: 1)
        _ = driver.tick(hub: &hub, now: 1)
        _ = hub.handle(.level(bus: .input, channel: 0, peakDB: -40), now: 1.1)
        XCTAssertFalse(driver.tick(hub: &hub, now: 1.2).midi.isEmpty, "the bar falls, the peak stays: redrawn")
        XCTAssertTrue(driver.tick(hub: &hub, now: 1.6).midi.filter { $0 == 0xF0 }.count <= 1, "held: nothing new, or a ring")
        XCTAssertFalse(driver.tick(hub: &hub, now: 2.3).midi.isEmpty, "after the hold, the peak drops: redrawn")
    }

    func testValuesHoldTheirPlaces() {
        func columns(_ text: String) -> [Int] {
            var screen = E16Screen()
            XCTAssertTrue(E16Driver.drawValue(text, cellX: 0, y: 0, on: &screen))
            return (0..<32).filter { x in (0..<7).contains { screen.pixel(x, $0) } }
        }
        let margin = (E16Screen.width / 4 - E16Driver.labelMaxWidth) / 2, right = margin + E16Driver.labelMaxWidth - 1
        for text in ["-6.0", "-12.5", "+2.5", "0.0", "-41.1"] {
            XCTAssertEqual(columns(text).last, right, "\(text): the tenths end at the right margin")
            XCTAssertTrue(columns(text).contains(right - 5) && !columns(text).contains(right - 4) && !columns(text).contains(right - 6), "\(text): the point in its place")
        }
        XCTAssertEqual(columns("L24").last, right, "a pan's last digit at the right margin")
        XCTAssertEqual(columns("C").last, right, "C at the right margin too")
        XCTAssertEqual(columns("-6.0").first, columns("-16.0").first.map { $0 + 5 }, "the sign moves a place when a digit is added")
        var screen = E16Screen()
        XCTAssertFalse(E16Driver.drawValue("Keys", cellX: 0, y: 0, on: &screen), "not a number")
    }

    func testMetersFollowTotalMixFXAtMost25ASecond() {
        var (driver, hub, _) = connectedFour()
        driver.drawsScreen = true
        driver.showsMeters = true
        driver.meterAverage = 0  // the bar follows at once, so only the rate limit is at work
        _ = driver.tick(hub: &hub, now: 1)
        func screens(_ midi: [UInt8]) -> Int { midi.sysExMessages.filter { $0.starts(with: Array(labelsID.prefix(7))) && !$0.starts(with: labelsID) && !$0.starts(with: ringsID) && !$0.starts(with: ledsID) }.count }
        _ = hub.handle(.level(bus: .input, channel: 0, peakDB: -6), now: 1.01)
        XCTAssertEqual(screens(driver.tick(hub: &hub, now: 1.05).midi), 1, "a level change redraws")
        _ = hub.handle(.level(bus: .input, channel: 0, peakDB: -3), now: 1.06)
        XCTAssertEqual(screens(driver.tick(hub: &hub, now: 1.07).midi), 0, "not within 1/25 s")
        XCTAssertEqual(screens(driver.tick(hub: &hub, now: 1.1).midi), 1, "then drawn")
        XCTAssertEqual(screens(driver.tick(hub: &hub, now: 1.2).midi), 0, "nothing changed")
    }

    func testSetOnlyMuteNameFlashes() {
        var (driver, hub, _) = connectedFour()
        driver.drawsScreen = true
        _ = driver.take(hub.handle(.other(path: "globalmute", value: .number(0)), now: 0.05), hub: &hub, now: 0.05)
        _ = driver.receive([0x90, 1, 0x7F, 0x80, 1, 0x00], hub: &hub, now: 0.1)  // Vox's mute, set only
        let framebufferID: [UInt8] = Array(labelsID.prefix(7))
        func screens(_ midi: [UInt8]) -> Int { midi.sysExMessages.filter { $0.starts(with: framebufferID) && !$0.starts(with: labelsID) && !$0.starts(with: ringsID) && !$0.starts(with: ledsID) }.count }
        _ = driver.tick(hub: &hub, now: 1.2)  // the title overlay ends
        XCTAssertEqual(screens(driver.tick(hub: &hub, now: 1.55).midi), 1, "the name drawn plain")
        XCTAssertEqual(screens(driver.tick(hub: &hub, now: 2.05).midi), 1, "and struck again")
        driver.marksNames = false
        _ = driver.tick(hub: &hub, now: 2.55)
        XCTAssertEqual(screens(driver.tick(hub: &hub, now: 3.05).midi), 0, "no flashing without name marks")
    }

    /// The 4-channel layout jumps the same way on every row (Adam, 2026-11-06).
    func testFourPushAndTurnJumps() {
        var (driver, hub, _) = connectedFour()
        _ = driver.receive([0x90, 12, 0x7F], hub: &hub, now: 1)  // Keys's level, pushed
        let turn = driver.receive([0xB0, 13, 0x04], hub: &hub, now: 1.1)
        XCTAssertEqual(turn.core.messages.first?.arguments.first, .float(Float(FaderCurve.unityPosition)), "to 0 dB")
        let release = driver.receive([0x80, 12, 0x00], hub: &hub, now: 1.2)
        XCTAssertFalse(release.core.messages.contains { $0.address.hasSuffix("mute") }, "the turn cancelled the push")
        _ = driver.receive([0x90, 8, 0x7F], hub: &hub, now: 2)  // Keys's pan, pushed
        let pan = driver.receive([0xB0, 9, 0x7E], hub: &hub, now: 2.1)
        XCTAssertTrue(pan.core.messages.first?.address.hasSuffix("balpan") ?? false)
        XCTAssertEqual(pan.core.messages.first?.arguments.first, .float(-1), "hard left")
        _ = driver.receive([0x80, 8, 0x00], hub: &hub, now: 2.2)
        _ = driver.receive([0x90, 0, 0x7F], hub: &hub, now: 3)  // Keys's send A, pushed
        let send = driver.receive([0xB0, 1, 0x02], hub: &hub, now: 3.1)
        XCTAssertEqual(send.core.messages.first?.arguments.first, .float(Float(FaderCurve.unityPosition)), "a send to 0 dB")
    }

    func testShortLevels() {
        XCTAssertEqual(E16Driver.shortLevel(0, width: nil), "-oo")
        let drawn = E16Driver.screen(title: "", labels: ["-oo"])
        var expected = E16Screen()
        let margin = (E16Screen.width / 4 - E16Driver.labelMaxWidth) / 2
        expected.line(y: 10, from: 0, to: E16Screen.width - 1)
        expected.draw("-∞", x: margin, y: E16Driver.labelTop)
        XCTAssertEqual(drawn, expected, "drawn with the infinity sign")
        var dash = E16Screen(), missing = E16Screen()
        dash.draw("∞", x: 0, y: 0)
        missing.draw("\u{1F600}", x: 0, y: 0)
        XCTAssertNotEqual(dash, missing, "a glyph of its own, not the box for a missing one")
        let centered = E16Driver.screen(title: "", labels: ["Vox"], centered: true)
        XCTAssertFalse(centered.pixel(margin, E16Driver.labelTop + 3), "not at the left")
        let left = (32 - E16Screen.width(of: "Vox")) / 2
        XCTAssertEqual(E16Driver.screen(title: "", labels: [""], centered: true), E16Driver.screen(title: "", labels: [""]))
        var vox = E16Screen()
        vox.line(y: 10, from: 0, to: E16Screen.width - 1)
        vox.draw("Vox", x: left, y: E16Driver.labelTop)
        XCTAssertEqual(centered, vox, "centered in its 32-pixel cell")
        XCTAssertEqual(E16Driver.shortLevel(FaderCurve.unityPosition, width: nil), "0.0")
        let low = E16Driver.shortLevel(0.3, width: nil)
        XCTAssertLessThanOrEqual(low.count, 4, "fits the firmware's four characters: \(low)")
        XCTAssertTrue(E16Screen.width(of: E16Driver.shortLevel(0.3, width: E16Driver.labelMaxWidth)) <= E16Driver.labelMaxWidth)
        var (driver, hub, _) = connectedFour()
        let off = driver.take(hub.handle(.mix(bus: .input, channel: 2, output: 2, parameter: "faderlin", value: .number(0)), now: 0.5), hub: &hub, now: 0.5)
        XCTAssertEqual(off.midi.lastLabels?[1], "", "a send that is off shows nothing")
        let turn = driver.receive([0xB0, 11, 0x0A], hub: &hub, now: 1)  // Gtr's pan, right
        XCTAssertTrue(turn.midi.lastLabels?[10].hasPrefix("R") == true, "the pan's label follows the turn")
    }

    func testHoldIsPFLWithTheCountdownOnTheLevelRing() {
        var (driver, hub, _) = connectedFour()
        _ = driver.receive([0x90, 2, 0x7F], hub: &hub, now: 1)  // row 1, Gtr
        let countdown = driver.tick(hub: &hub, now: 1.5).midi
        XCTAssertEqual(countdown.rings[14]?.r, E16Driver.pflRGB.0, "the pink arc on Gtr's level ring")
        XCTAssertEqual(countdown.rings[14]?.b, E16Driver.pflRGB.2)
        XCTAssertNil(countdown.rings[2], "not on the encoder pushed")
        let pfl = driver.tick(hub: &hub, now: 2.05)
        XCTAssertEqual(pfl.core.messages.map(\.address), ["/input/3/pfl"])
        let release = driver.receive([0x80, 2, 0x00], hub: &hub, now: 2.1).midi + driver.tick(hub: &hub, now: 2.3).midi
        XCTAssertEqual(release.leds[14]?.count, 4, "PFL's marks on the level ring")
        XCTAssertEqual(release.leds[14]?.first?.b, E16Driver.pflRGB.2)
        XCTAssertNil(release.leds[2], "the send ring keeps its value")
    }

    func testNamesFitAsASet() {
        let names = ["ADI-2 3/4", "ADAT 1/2", "ADAT 3/4"]
        let arrows = E16Driver.fitSet(names, width: 28 - E16Screen.width(of: "<"))
        XCTAssertEqual(Set(arrows.map { $0.uppercased() }).count, 3, "no two alike: \(arrows)")
        let title = E16Driver.fitSet(names, width: 31)
        XCTAssertEqual(title.map { $0.uppercased() }, ["ADI3/4", "ADT1/2", "ADT3/4"], "the model number goes first: \(title)")
        XCTAssertEqual(E16Driver.fitSet(["Keys", "Keys"], width: 26), ["Keys", "Keys"], "the same name stays the same")
    }

    func testShiftRowsShowTheCurrentOutputs() {
        var (driver, hub, _) = connectedFour()
        let labels = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 1).midi.lastLabels ?? []
        XCTAssertEqual(labels[0], "Phon", "send A's output, in the firmware's four characters: \(labels)")
        XCTAssertEqual(labels[4], "Mon", "send B's")
        XCTAssertEqual(labels[1], "")
        var screen = E16Screen()
        screen = E16Driver.screen(title: "", labels: ["A: ADI 3/4"], centered: true, spans: [0])
        let margin = (E16Screen.width / 4 - E16Driver.labelMaxWidth) / 2
        XCTAssertTrue((E16Driver.labelTop..<E16Driver.labelTop + 7).contains { screen.pixel(margin, $0) }, "from the first cell's margin, not centered")
    }

    func testShiftPageStepsTheSendRows() {
        var (driver, hub, _) = connectedFour()
        let shift = driver.receive([0x90, 16, 0x7F], hub: &hub, now: 1)
        XCTAssertEqual(shift.midi.lastLabels, ["Phon", "", "", ">", "Mon", "", "", ">",
                                               "", "", "", "", "16CH", "STRP", "", ""],
                       "A's back arrow and B's go nowhere (B's would be A's output); one page")
        XCTAssertEqual(shift.midi.rings[3]?.g, 2, "an available arrow, dim deep green")
        XCTAssertEqual(shift.midi.rings[2]?.amount, 0, "dark")
        let press = driver.receive([0x90, 3, 0x7F, 0x80, 3, 0x00], hub: &hub, now: 2)  // A forward
        XCTAssertEqual(driver.currentSendOutputs(hub: hub), [6, 4], "A skips B's output")
        XCTAssertEqual(driver.sendOutputs, [6, 4])
        XCTAssertEqual(press.midi.lastTitle, "A>ROO B>MON")
        XCTAssertEqual(press.midi.lastLabels?[2], "<", "A's back arrow, plain; it skips Mon, B's output")
        _ = driver.receive([0x90, 16, 0x00], hub: &hub, now: 3)
        XCTAssertEqual(driver.receive([0xB0, 1, 0x04], hub: &hub, now: 4).core.messages.map(\.address), ["/mix/in/0/6/faderlin"], "send A now to Room")
    }
}
