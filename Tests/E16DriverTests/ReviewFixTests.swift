import XCTest
import OSCCodec
import TotalMixOSC
import OXIE16
import SurfaceCore
@testable import E16Driver

// The 1.2.0 review's findings (2026-11-07), as tests.

/// `sources` mono inputs ("In1"…), outputs Main 1/2 (Main Out), Phones 3/4, and Mon 5/6.
private func reviewHub(sources: Int = 4) -> SurfaceHub {
    var hub = SurfaceHub()
    var events: [TotalMixEvent] = []
    func channel(_ bus: TotalMixBus, _ number: Int, _ name: String, stereo: Bool) {
        events.append(.channel(bus: bus, channel: number, parameter: "stereo", value: .number(stereo ? 1 : 0)))
        events.append(.channel(bus: bus, channel: number, parameter: "name", value: .text(name)))
        events.append(.channel(bus: bus, channel: number, parameter: "color", value: .number(1)))
        events.append(.channel(bus: bus, channel: number, parameter: "mute", value: .number(0)))
        events.append(.channel(bus: bus, channel: number, parameter: "pfl", value: .number(0)))
    }
    for n in 0..<sources { channel(.input, n, "In\(n + 1)", stereo: false) }
    channel(.output, 0, "Main", stereo: true)
    channel(.output, 2, "Phones", stereo: true)
    channel(.output, 4, "Mon", stereo: true)
    events.append(.channel(bus: .output, channel: 0, parameter: "faderlin", value: .number(0.8)))
    for n in 0..<sources {
        for output in [0, 2, 4] {
            events.append(.mix(bus: .input, channel: n, output: output, parameter: "faderlin", value: .number(0.5)))
            events.append(.mix(bus: .input, channel: n, output: output, parameter: "balpan", value: .number(0)))
        }
    }
    events.append(.other(path: "controlroom/mainout", value: .number(0)))
    for event in events { _ = hub.handle(event, now: 0) }
    return hub
}

private let reviewAck: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x53, 0xF7]
private let reviewRingsID: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x04]

private func bipolar(_ midi: [UInt8], encoder: Int) -> Bool? {
    var result: Bool?
    var current: [UInt8]?
    for byte in midi {
        if byte == 0xF0 { current = [byte] } else if var c = current {
            c.append(byte)
            if byte == 0xF7 {
                if c.starts(with: reviewRingsID) {
                    let raw = E16Outgoing.unpack(Array(c[8..<(c.count - 1)]))
                    var i = 0
                    while i + 7 <= raw.count { if Int(raw[i]) == encoder { result = raw[i + 6] == 1 }; i += 7 }
                }
                current = nil
            } else { current = c }
        }
    }
    return result
}

final class ReviewFixTests: XCTestCase {
    func testTheLevelRowIsALevelAfterPANMode() {
        var hub = reviewHub()
        var driver = E16Driver(name: "e16")
        driver.drawsScreen = false
        _ = driver.start(hub: &hub, now: 0)
        _ = driver.receive(reviewAck, hub: &hub, now: 0.3)
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 1, 0x7F, 0x80, 1, 0x00], hub: &hub, now: 0.5)  // Shift + 2: PAN
        XCTAssertEqual(driver.function, .pan)
        let onDevice = driver.receive([0x90, 13, 0x7F, 0x80, 13, 0x00, 0x90, 16, 0x00], hub: &hub, now: 0.6)  // Shift + 14
        XCTAssertEqual(driver.layout, .four)
        XCTAssertEqual(bipolar(onDevice.midi, encoder: 12), false, "the bottom row is a level, not a pan")

        var hub2 = reviewHub()
        var other = E16Driver(name: "e16")
        other.drawsScreen = false
        _ = other.start(hub: &hub2, now: 0)
        _ = other.receive(reviewAck, hub: &hub2, now: 0.3)
        _ = other.receive([0x90, 16, 0x7F, 0x90, 1, 0x7F, 0x80, 1, 0x00, 0x80, 16, 0x00], hub: &hub2, now: 0.5)
        let fromApp = other.setLayout(.four, hub: &hub2, now: 0.6)
        XCTAssertEqual(bipolar(fromApp.midi, encoder: 12), false, "the same when Settings switches the layout")
    }

    func testATurnHeldAtCenterSendsNothing() {
        var hub = reviewHub()
        var driver = E16Driver(name: "e16")
        driver.drawsScreen = false
        _ = driver.start(hub: &hub, now: 0)
        _ = driver.receive(reviewAck, hub: &hub, now: 0)
        _ = driver.receive([0x90, 16, 0x7F, 0x90, 1, 0x7F, 0x80, 1, 0x00, 0x80, 16, 0x00], hub: &hub, now: 1)  // PAN
        for t in [3.0, 4.0] {
            let step = driver.receive([0xB0, 1, 0x01], hub: &hub, now: t)
            XCTAssertTrue(step.core.messages.isEmpty, "held at center: nothing sent to TotalMix FX")
            XCTAssertEqual(driver.title(hub: hub), "In1 C", "the title still shows the pan")
        }
        let leave = driver.receive([0xB0, 1, 0x01], hub: &hub, now: 5)
        XCTAssertFalse(leave.core.messages.isEmpty, "leaving center is sent")
    }

    func testALayoutSetBeforeTheDeviceAnswersStartsAfresh() {
        var hub = reviewHub(sources: 8)
        var driver = E16Driver(name: "e16")
        driver.drawsScreen = true
        _ = driver.start(hub: &hub, now: 0)
        _ = driver.take(hub.resend(driver.id(.main), now: 0.1), hub: &hub, now: 0.1)  // TotalMix FX's state first
        XCTAssertTrue(driver.setLayout(.four, hub: &hub, now: 0.2).midi.isEmpty, "nothing drawn before the answer")
        _ = driver.receive(reviewAck, hub: &hub, now: 0.3)
        _ = driver.take(hub.handle(.channel(bus: .input, channel: 5, parameter: "pfl", value: .number(1)), now: 1), hub: &hub, now: 1)
        XCTAssertTrue(driver.titleParts(hub: hub).1.contains("■"), "In6 is on page 2: its PFL shows in the title")
    }

    /// PFL's square on a full-width name stays in its cell, in column 4 too, and a box around a
    /// muted and PFL'd name stays clear of the next cell's name.
    func testPFLSquareStaysInItsCell() {
        let labels = ["", "", "3RD W", "MIC24"]
        let screen = E16Driver.screen(title: "LEVEL", labels: labels, inverted: [2], pflMarked: [2, 3], centered: true)
        let y = E16Driver.labelTop
        // Column 4: the square's three columns, ending on the screen.
        let width = E16Screen.width(of: "MIC24")
        let x = 96 + (32 - width - 5) / 2
        XCTAssertLessThanOrEqual(x + width + 4, 127, "the square ends on the screen")
        for px in (x + width + 2)...(x + width + 4) { XCTAssertTrue(screen.pixel(px, y + 3), "square column \(px)") }
        // Column 3: the box around "3RD W" and its square ends before column 4 begins.
        for py in (y - 1)...(y + 7) { XCTAssertFalse(screen.pixel(96, py), "x 96 clear at y \(py)") }
    }

    /// One output, one short form: the full name where it fits, otherwise the 4-channel title's.
    func testAnOutputHasOneShortForm() {
        var hub = SurfaceHub()
        for (n, name) in [(0, "Main"), (2, "ADI-2 3/4"), (4, "ADAT 1/2")] {
            _ = hub.handle(.channel(bus: .output, channel: n, parameter: "stereo", value: .number(1)), now: 0)
            _ = hub.handle(.channel(bus: .output, channel: n, parameter: "name", value: .text(name)), now: 0)
        }
        _ = hub.handle(.other(path: "controlroom/mainout", value: .number(0)), now: 0)
        let driver = E16Driver(name: "e16")
        guard let adi = hub.sendTargets.firstIndex(of: 2) else { return XCTFail("no ADI-2 3/4 target") }
        let short = driver.outputForm(adi, room: E16Driver.outputShortWidth, hub: hub)
        XCTAssertNotEqual(short, "ADI-2 3/4")
        XCTAssertEqual(driver.outputForm(adi, room: 34, hub: hub), short, "the overlay's room: the same short form")
        XCTAssertEqual(driver.outputForm(adi, room: 120, hub: hub), "ADI-2 3/4", "the full name where it fits")
    }

    /// A mute's flash while Mute Master is off: the box's outline in the off phase.
    func testMuteFlashOffPhaseIsAnOutline() {
        let plain = E16Driver.screen(title: "LEVEL", labels: ["VOX"], centered: true)
        let outline = E16Driver.screen(title: "LEVEL", labels: ["VOX"], outlined: [0], centered: true)
        let y = E16Driver.labelTop
        let added = (0..<32).filter { x in outline.pixel(x, y - 2) && !plain.pixel(x, y - 2) }
        XCTAssertGreaterThan(added.count, 10, "a line over the name")
        let x = (32 - E16Screen.width(of: "VOX")) / 2
        XCTAssertFalse((x..<(x + E16Screen.width(of: "VOX"))).contains { outline.pixel($0, y - 1) },
                       "one clear pixel between the outline and the letters")
        XCTAssertFalse((y..<(y + 7)).contains { outline.pixel(x - 1, $0) }, "and at the side")
        XCTAssertEqual(plain.pixel(16, y + 3), outline.pixel(16, y + 3), "the name itself unchanged")
    }
}
