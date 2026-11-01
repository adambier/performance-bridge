import XCTest
@testable import LaunchControlXL3

/// Checks the Launch Control XL 3's messages against Novation's programmer's reference guide,
/// version 1.0. These are checks of this library against the guide, not of the device.
final class LaunchControlXL3Tests: XCTestCase {
    func testControlNumbersFollowTheGuidesMap() {
        XCTAssertEqual(LaunchControlElement.fader(0).controlNumber, 5)
        XCTAssertEqual(LaunchControlElement.fader(7).controlNumber, 12)
        XCTAssertEqual(LaunchControlElement.encoder(row: 0, column: 0).controlNumber, 13)
        XCTAssertEqual(LaunchControlElement.encoder(row: 1, column: 0).controlNumber, 21)
        XCTAssertEqual(LaunchControlElement.encoder(row: 2, column: 7).controlNumber, 36)
        XCTAssertEqual(LaunchControlElement.button(row: 0, column: 0).controlNumber, 37)
        XCTAssertEqual(LaunchControlElement.button(row: 1, column: 7).controlNumber, 52)
        XCTAssertEqual(LaunchControlElement.trackLeft.controlNumber, 103)
        XCTAssertEqual(LaunchControlElement.trackRight.controlNumber, 102)
        XCTAssertEqual(LaunchControlElement.pageUp.controlNumber, 106)
        XCTAssertEqual(LaunchControlElement.shift.reportChannel, 6)
        XCTAssertEqual(LaunchControlElement.fader(3).reportChannel, 15)
        XCTAssertEqual(LaunchControlElement.record.reportChannel, 0)
    }

    func testEveryControlIsFoundAgainFromItsNumber() {
        XCTAssertEqual(LaunchControlElement.all.count, 8 + 24 + 16 + 10)
        XCTAssertEqual(Set(LaunchControlElement.all.map { "\($0.reportChannel)/\($0.controlNumber)" }).count,
                       LaunchControlElement.all.count, "no two controls share a channel and number")
        for element in LaunchControlElement.all {
            XCTAssertEqual(LaunchControlElement(channel: element.reportChannel, controlNumber: element.controlNumber), element)
        }
        XCTAssertNil(LaunchControlElement(channel: 0, controlNumber: 5), "faders report on channel 16, not 1")
        XCTAssertFalse(LaunchControlElement.fader(8).isValid)
    }

    func testModesUseTheFeatureControlTablesValues() {
        XCTAssertEqual(LaunchControlMode(value: 1), .dawMixer)
        XCTAssertEqual(LaunchControlMode(value: 2), .dawControl)
        XCTAssertEqual(LaunchControlMode(value: 6), .custom(1))
        XCTAssertEqual(LaunchControlMode(value: 9), .custom(4))
        XCTAssertEqual(LaunchControlMode(value: 18), .custom(5))
        XCTAssertEqual(LaunchControlMode(value: 29), .custom(16))
        XCTAssertNil(LaunchControlMode(value: 10))
        for number in 1...16 {
            XCTAssertEqual(LaunchControlMode.custom(number).value.flatMap(LaunchControlMode.init(value:)), .custom(number))
        }
        XCTAssertNil(LaunchControlMode.custom(17).value)
    }

    func testDAWModeAndFeatureControls() {
        XCTAssertEqual(LaunchControlOutgoing.dawMode(true), [0x9F, 0x0C, 0x7F])
        XCTAssertEqual(LaunchControlOutgoing.dawMode(false), [0x9F, 0x0C, 0x00])
        XCTAssertEqual(LaunchControlOutgoing.dawModeSysEx(true), [0xF0, 0x00, 0x20, 0x29, 0x02, 0x15, 0x02, 0x7F, 0xF7])
        XCTAssertEqual(LaunchControlOutgoing.featureControls(true), [0x9F, 0x0B, 0x7F])
        XCTAssertEqual(LaunchControlOutgoing.selectMode(.dawMixer), [0xB6, 0x1E, 0x01])
        XCTAssertEqual(LaunchControlOutgoing.relativeEncoders(row: 1, true), [0xB6, 0x48, 0x7F])
        XCTAssertNil(LaunchControlOutgoing.relativeEncoders(row: 3, true))
        XCTAssertEqual(LaunchControlOutgoing.faderPickup(true), [0xB6, 0x46, 0x7F])
        XCTAssertEqual(LaunchControlOutgoing.touchEvents(false), [0xB6, 0x47, 0x00])
        XCTAssertEqual(LaunchControlOutgoing.queryFeature(0x70), [0xB7, 0x70, 0x00])
        XCTAssertEqual(LaunchControlOutgoing.displayTimeout(tenths: 200), [0xB6, 0x71, 99])
    }

    func testColors() {
        XCTAssertEqual(LaunchControlOutgoing.color(.button(row: 0, column: 0), 5), [0xB0, 37, 5])
        XCTAssertEqual(LaunchControlOutgoing.color(.encoder(row: 2, column: 0), 0x25), [0xB0, 29, 0x25])
        XCTAssertNil(LaunchControlOutgoing.color(.fader(0), 5), "faders have no LED")
        XCTAssertNil(LaunchControlOutgoing.color(.shift, 5), "Shift's light is its feature control's")
        XCTAssertEqual(LaunchControlOutgoing.rgb(.play, red: 127, green: 64, blue: 200),
                       [0xF0, 0x00, 0x20, 0x29, 0x02, 0x15, 0x01, 0x53, 116, 127, 64, 0x48, 0xF7],
                       "SysEx data bytes keep to 7 bits")
    }

    func testDisplays() {
        XCTAssertEqual(LaunchControlOutgoing.configureDisplay(.control(.fader(0)), .nameAndValue),
                       [0xF0, 0x00, 0x20, 0x29, 0x02, 0x15, 0x04, 0x05, 0x61, 0xF7])
        XCTAssertEqual(LaunchControlOutgoing.configureDisplay(.stationary, .titleNameAndValue, onChange: false, onTouch: false),
                       [0xF0, 0x00, 0x20, 0x29, 0x02, 0x15, 0x04, 0x35, 0x02, 0xF7])
        XCTAssertEqual(LaunchControlOutgoing.showDisplay(.overlay, true), [0xF0, 0x00, 0x20, 0x29, 0x02, 0x15, 0x04, 0x36, 0x7F, 0xF7])
        XCTAssertNil(LaunchControlOutgoing.configureDisplay(.control(.play), .nameAndValue), "only faders and encoders have displays")
        XCTAssertEqual(LaunchControlOutgoing.text(.control(.encoder(row: 0, column: 0)), field: 1, "-6.0 dB"),
                       [0xF0, 0x00, 0x20, 0x29, 0x02, 0x15, 0x06, 13, 1] + Array("-6.0 dB".utf8) + [0xF7])
        XCTAssertEqual(LaunchControlArrangement.titleAndEightNames.fieldCount, 9)
    }

    func testTextIsMadeFitForTheScreen() {
        XCTAssertEqual(LaunchControlText.bytes("> Phones"), Array("> Phones".utf8))
        XCTAssertEqual(LaunchControlText.bytes("Café"), Array("Cafe".utf8))
        XCTAssertEqual(LaunchControlText.bytes("\u{2212}6 dB \u{2192} Main"), Array("-6 dB > Main".utf8))
        XCTAssertEqual(LaunchControlText.bytes("\u{2665}\u{266D}"), [0x1E, 0x1D])
        XCTAssertEqual(LaunchControlText.bytes("日"), [0x3F])
        XCTAssertTrue(LaunchControlText.bytes("Tab\there\u{1}").allSatisfy { (0x20...0x7E).contains($0) },
                      "no control codes other than the four symbols")
    }

    func testPositions() {
        XCTAssertEqual(LaunchControlOutgoing.position(.encoder(row: 0, column: 1), 100), [0xBF, 14, 100])
        XCTAssertEqual(LaunchControlOutgoing.position(.fader(7), 0), [0xBF, 12, 0])
        XCTAssertNil(LaunchControlOutgoing.position(.record, 1))
    }

    func testEventsFromChannelMessages() {
        XCTAssertEqual(LaunchControlEvent(status: 0xBF, 5, 64), .moved(.fader(0), value: 64))
        XCTAssertEqual(LaunchControlEvent(status: 0xBF, 36, 1), .moved(.encoder(row: 2, column: 7), value: 1))
        XCTAssertEqual(LaunchControlEvent(status: 0xBF, 77, 65), .turned(.encoder(row: 0, column: 0), steps: 1))
        XCTAssertEqual(LaunchControlEvent(status: 0xBF, 100, 63), .turned(.encoder(row: 2, column: 7), steps: -1))
        XCTAssertEqual(LaunchControlEvent(status: 0xBE, 5, 127), .touch(.fader(0), touched: true), "the guide's own example")
        XCTAssertEqual(LaunchControlEvent(status: 0xBE, 5, 0), .touch(.fader(0), touched: false))
        XCTAssertEqual(LaunchControlEvent(status: 0xB0, 37, 127), .button(.button(row: 0, column: 0), pressed: true))
        XCTAssertEqual(LaunchControlEvent(status: 0xB0, 103, 0), .button(.trackLeft, pressed: false))
        XCTAssertEqual(LaunchControlEvent(status: 0xB6, 0x3F, 127), .button(.shift, pressed: true))
        XCTAssertEqual(LaunchControlEvent(status: 0xB6, 0x1E, 2), .mode(.dawControl))
        XCTAssertEqual(LaunchControlEvent(status: 0xB6, 0x70, 90), .feature(number: 0x70, value: 90))
        XCTAssertEqual(LaunchControlEvent(status: 0x90, 1, 1), .unknown([0x90, 1, 1]))
        XCTAssertEqual(LaunchControlEvent(status: 0x9F, 0x0C, 0x7F), .dawMode(true), "seen on the device")
        XCTAssertEqual(LaunchControlEvent(status: 0x9F, 0x0C, 0x00), .dawMode(false))
        XCTAssertEqual(LaunchControlEvent(status: 0xBE, 0x4D, 0x7F), .touch(.encoder(row: 0, column: 0), touched: true),
                       "a relative row's touch reports use its relative numbers (seen)")
    }

    func testParserHandlesSplitMessagesRunningStatusAndSysEx() {
        var parser = LaunchControlParser()
        XCTAssertEqual(parser.feed([0xBF, 5]), [])
        XCTAssertEqual(parser.feed([10, 6, 20, 0xF8, 7, 30]),
                       [.moved(.fader(0), value: 10), .moved(.fader(1), value: 20), .moved(.fader(2), value: 30)],
                       "running status, with a clock byte in between")
        XCTAssertEqual(parser.feed(LaunchControlOutgoing.sysExHeader + [0x09, 0x7F, 0xF7] + [0xB0, 116, 127]),
                       [.bitmapReady, .button(.play, pressed: true)])
        XCTAssertEqual(parser.feed(LaunchControlOutgoing.sysExHeader + [0x09, 0xF7]), [.bitmapReady],
                       "the reply read with the guide's 7Fh as a misprint for F7h")
        XCTAssertEqual(parser.feed(LaunchControlOutgoing.sysExHeader + [0x09] + [0xB0, 118, 127]),
                       [.button(.record, pressed: true)], "an unfinished SysEx message is dropped")
    }
}
