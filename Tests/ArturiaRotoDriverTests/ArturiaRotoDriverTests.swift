import XCTest
@testable import ArturiaRotoDriver
import RotoControl
import ArturiaControl

/// The instrument's messages below are written from the layouts in docs/ARTURIA.md, section 3.
final class ArturiaRotoDriverTests: XCTestCase {
    /// The instrument's value message for an item.
    private func value(_ item: UInt8, _ value: UInt8) -> [UInt8] {
        [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x02, 0x00, 0x00, item, value, 0xF7]
    }

    /// The instrument's text message with an instrument's name and a preset's name.
    private func text(_ instrument: String, _ preset: String) -> [UInt8] {
        var bytes: [UInt8] = [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x04, 0x00, 0x60]
        bytes += [0x01] + Array(instrument.utf8) + [0x00]
        bytes += [0x02] + Array(preset.utf8) + [0x00]
        bytes += [0x03] + Array("Bells".utf8) + [0x00, 0x04, 0x00, 0xF7]
        return bytes
    }

    private func learn(_ number: Int, _ name: String, _ position: Int) -> ArturiaRotoDeviceMessage {
        .message(.learnParameter(.macro(number, name: name, position: position)))
    }

    private func rename(_ number: Int, _ name: String) -> ArturiaRotoDeviceMessage {
        .message(.mappedControlName(parameterIndex: number, hash: .macroParameter(number), name: name))
    }

    private func show(_ knob: Int, _ text: String) -> ArturiaRotoDeviceMessage {
        .message(.showValue(.knob, control: knob, text: text))
    }

    /// The plugin list, then DAW SELECT PLUGIN for plugin 0 with the macro page, not forced.
    private func pluginList(_ name: String, page: Int = 0) -> [ArturiaRotoDeviceMessage] {
        [.message(.pluginCount(1)), .message(.firstPlugin(0)),
         .message(.pluginDetails(.macro(index: 0, name: name, pages: 2))), .message(.pluginDetailsEnd),
         .message(.dawSelectPlugin(index: 0, macroPage: page, force: false))]
    }

    private func driverInPluginMode(wait: Bool = false) -> ArturiaRotoDriver {
        var driver = ArturiaRotoDriver(waitsForControlMapped: wait)
        _ = driver.fromDevice(.message(.pluginMode), now: 0)
        return driver
    }

    func testValueScaling() {
        XCTAssertEqual(ArturiaRotoDriver.position(forValue: 0), 0)
        XCTAssertEqual(ArturiaRotoDriver.position(forValue: 64), 8256, "64 × 16383 ÷ 127 = 8255.9")
        XCTAssertEqual(ArturiaRotoDriver.position(forValue: 127), 16383)
        XCTAssertEqual(ArturiaRotoDriver.value(forPosition: 0), 0)
        XCTAssertEqual(ArturiaRotoDriver.value(forPosition: 8192), 64, "8192 × 127 ÷ 16383 = 63.5")
        XCTAssertEqual(ArturiaRotoDriver.value(forPosition: 16383), 127)
        for value in 0...127 {
            XCTAssertEqual(ArturiaRotoDriver.value(forPosition: ArturiaRotoDriver.position(forValue: value)), value)
        }
        XCTAssertEqual(ArturiaRotoDriver.valueText(0), "0%")
        XCTAssertEqual(ArturiaRotoDriver.valueText(74), "58%")
        XCTAssertEqual(ArturiaRotoDriver.valueText(127), "100%")
    }

    func testNothingGoesToTheDeviceOutsidePluginMode() {
        var driver = ArturiaRotoDriver()
        XCTAssertTrue(driver.fromInstrument(value(1, 64), now: 0).isEmpty)
        XCTAssertTrue(driver.fromInstrument(text("Pigments", "*Welcome"), now: 0).isEmpty)
        XCTAssertTrue(driver.fromDevice(.control(.knob(0, position: 8192)), now: 0).isEmpty)
        XCTAssertTrue(driver.tick(now: 1).isEmpty)
        XCTAssertEqual(driver.value(forItem: 1), 64, "kept for later")
        XCTAssertEqual(driver.pluginName, "Pigments")
    }

    func testEnteringPluginModeSendsThePluginAndThePage() {
        var driver = ArturiaRotoDriver()
        _ = driver.fromInstrument(value(2, 127), now: 0)
        let output = driver.fromDevice(.message(.pluginMode), now: 1)
        var expected = pluginList("Arturia")
        expected += [learn(1, "Macro 1?", 0), learn(2, "Macro 2", 16383), learn(3, "Macro 3?", 0), learn(4, "Macro 4?", 0),
                     learn(5, "Param 1?", 0), learn(6, "Param 2?", 0), learn(7, "Param 3?", 0), learn(8, "Param 4?", 0)]
        // Only the knob whose value is known is sent a position.
        expected += [.knob(1, position: 16383)]
        XCTAssertEqual(output.toDevice, expected)
        XCTAssertEqual(output.toInstrument, [])
        XCTAssertTrue(driver.isInPluginMode)
        // The bytes of the first LEARN PARAM: macro number 1, the macro flag, and the name.
        let bytes = expected[5].bytes
        XCTAssertEqual(Array(bytes[5...8]), [0x0B, 0x0A, 0x00, 0x01])
        XCTAssertEqual(bytes[15], 0x01, "the macro flag")
        XCTAssertEqual(Array(bytes[20..<28]), Array("Macro 1?".utf8))

        _ = driver.fromDevice(.message(.allTracksMode(RotoAllTracksMode(trackSet: .audio, knobMode: .level, switchMode: .mute, sendIndex: 0))), now: 2)
        XCTAssertFalse(driver.isInPluginMode)
    }

    func testWaitingStyleAnswersControlMapped() {
        var driver = ArturiaRotoDriver(waitsForControlMapped: true)
        let output = driver.fromDevice(.message(.pluginMode), now: 0)
        XCTAssertEqual(output.toDevice, pluginList("Arturia"))
        let mapping = RotoControlMapping(parameterIndex: 5, parameterHash: .macroParameter(5), kind: .knob, control: 4, isMacro: true)
        XCTAssertEqual(driver.fromDevice(.message(.controlMapped(mapping)), now: 0).toDevice, [learn(5, "Param 1?", 0)])
        // On the second page only macro 1 has a control.
        XCTAssertEqual(driver.fromDevice(.message(.macroPage(1)), now: 0).toDevice, [])
        XCTAssertEqual(driver.fromDevice(.message(.controlMapped(mapping)), now: 0).toDevice, [])
        // The unasked style answers CONTROL MAPPED too.
        var unasked = driverInPluginMode()
        XCTAssertEqual(unasked.fromDevice(.message(.controlMapped(mapping)), now: 0).toDevice, [learn(5, "Param 1?", 0)])
    }

    func testUnknownThenKnownFromTheInstrument() {
        var driver = driverInPluginMode()
        let output = driver.fromInstrument(value(9, 74), now: 1)
        // Item 9 is knob 5 (Param 1): the name without "?", the position, and the value's text.
        XCTAssertEqual(output.toDevice, [rename(5, "Param 1"), .knob(4, position: ArturiaRotoDriver.position(forValue: 74)), show(4, "58%")])
        XCTAssertEqual(output.toInstrument, [], "a value the instrument reported is not sent back to it")
        // A second value: no name again.
        XCTAssertEqual(driver.fromInstrument(value(9, 0), now: 2).toDevice, [.knob(4, position: 0), show(4, "0%")])
        // An item on the other page is only kept.
        XCTAssertTrue(driver.fromInstrument(value(8, 86), now: 3).isEmpty)
        XCTAssertEqual(driver.value(forItem: 8), 86)
        // An item with no control at all.
        XCTAssertTrue(driver.fromInstrument(value(48, 5), now: 3).isEmpty)
    }

    func testAnUnknownValueSendsNoKnobPositionAndAFirstValueOfZeroMovesTheKnob() {
        var driver = driverInPluginMode()
        // Nothing was known on entering PLUGIN mode, so no knob was sent a position, and the
        // first value moves its knob even when it is 0.
        XCTAssertEqual(driver.fromInstrument(value(1, 0), now: 1).toDevice, [rename(1, "Macro 1"), .knob(0, position: 0), show(0, "0%")])
        // The same after CONTROL MAPPED for an unknown value, whose LEARN PARAM carries 0.
        let mapping = RotoControlMapping(parameterIndex: 2, parameterHash: .macroParameter(2), kind: .knob, control: 1, isMacro: true)
        XCTAssertEqual(driver.fromDevice(.message(.controlMapped(mapping)), now: 2).toDevice, [learn(2, "Macro 2?", 0)])
        XCTAssertEqual(driver.fromInstrument(value(2, 0), now: 3).toDevice, [rename(2, "Macro 2"), .knob(1, position: 0), show(1, "0%")])
        // A page of unknown values: LEARN PARAM alone.
        XCTAssertEqual(driver.fromDevice(.message(.macroPage(1)), now: 4).toDevice, [learn(1, "Volume?", 0)])
        // The device selecting the plugin sends the page again: positions for the known only.
        _ = driver.fromDevice(.message(.macroPage(0)), now: 5)
        let selected = driver.fromDevice(.message(.selectPlugin(0)), now: 6).toDevice
        XCTAssertEqual(selected.count, 10)
        XCTAssertEqual(Array(selected.suffix(2)), [.knob(0, position: 0), .knob(1, position: 0)])
    }

    func testSetFirstPluginSendsTheListAndTheSelection() {
        var driver = driverInPluginMode()
        XCTAssertEqual(driver.fromDevice(.message(.setFirstPlugin(0)), now: 1).toDevice, pluginList("Arturia"))
        XCTAssertEqual(driver.fromDevice(.message(.setFirstPlugin(8)), now: 1).toDevice, [])
        // The selection carries the macro page shown.
        _ = driver.fromDevice(.message(.macroPage(1)), now: 2)
        XCTAssertEqual(driver.fromDevice(.message(.setFirstPlugin(0)), now: 3).toDevice, pluginList("Arturia", page: 1))
    }

    func testUnknownThenKnownFromTheKnob() {
        var driver = driverInPluginMode()
        let output = driver.fromDevice(.control(.knob(0, position: 8192)), now: 1)
        XCTAssertEqual(output.toInstrument, [[0xB0, 74, 64]], "Macro 1 is control change 74 on channel 1")
        XCTAssertEqual(output.toDevice, [rename(1, "Macro 1"), show(0, "50%")])
        XCTAssertEqual(driver.value(forItem: 1), 64)
    }

    func testAKnobReportEqualToTheLastValueSendsNothing() {
        var driver = driverInPluginMode()
        _ = driver.fromDevice(.control(.knob(1, position: 8192)), now: 1)
        // 8200 is still 64 in 7 bits.
        XCTAssertTrue(driver.fromDevice(.control(.knob(1, position: 8200)), now: 2).isEmpty)
        // Equal to a value the instrument reported.
        _ = driver.fromInstrument(value(3, 127), now: 3)
        XCTAssertTrue(driver.fromDevice(.control(.knob(2, position: 16383)), now: 4).isEmpty)
        // A change is sent: Macro 2 is control change 71.
        XCTAssertEqual(driver.fromDevice(.control(.knob(1, position: 16383)), now: 5).toInstrument, [[0xB0, 71, 127]])
        // Switches, touches, and knobs without a control send nothing.
        XCTAssertTrue(driver.fromDevice(.control(.switch(0, value: 127)), now: 6).isEmpty)
        XCTAssertTrue(driver.fromDevice(.control(.touch(0, touched: true)), now: 6).isEmpty)
        _ = driver.fromDevice(.message(.macroPage(1)), now: 7)
        XCTAssertTrue(driver.fromDevice(.control(.knob(3, position: 100)), now: 8).isEmpty)
    }

    func testAValueFromTheInstrumentWaitsWhileItsKnobIsTurned() {
        var driver = driverInPluginMode()
        _ = driver.fromDevice(.control(.knob(0, position: 8192)), now: 1.0)   // 64
        // 0.1 s later the instrument reports another value: the knob is not moved yet.
        XCTAssertEqual(driver.fromInstrument(value(1, 100), now: 1.1).toDevice, [show(0, "79%")])
        XCTAssertTrue(driver.tick(now: 1.2).isEmpty, "still inside the 0.25 s")
        XCTAssertEqual(driver.tick(now: 1.26).toDevice, [.knob(0, position: ArturiaRotoDriver.position(forValue: 100))])
        XCTAssertTrue(driver.tick(now: 1.3).isEmpty, "sent once")

        // Each report from the knob starts the hold again, and a held value equal to what the
        // knob last reported is not sent.
        _ = driver.fromDevice(.control(.knob(0, position: 0)), now: 2.0)
        _ = driver.fromInstrument(value(1, 50), now: 2.1)
        let turned = driver.fromDevice(.control(.knob(0, position: ArturiaRotoDriver.position(forValue: 50))), now: 2.2)
        XCTAssertEqual(turned.toInstrument, [], "the instrument already has 50")
        XCTAssertTrue(driver.tick(now: 2.3).isEmpty, "2.0 + 0.25 has passed, but the knob moved at 2.2")
        XCTAssertEqual(driver.tick(now: 2.5).toDevice.filter { if case .knob = $0 { return true } else { return false } }, [])

        // After the hold, a value moves the knob at once.
        XCTAssertEqual(driver.fromInstrument(value(1, 0), now: 3.0).toDevice.first, .knob(0, position: 0))
    }

    func testValueTextIsLimitedWithATrailingUpdate() {
        var driver = driverInPluginMode()
        XCTAssertEqual(driver.fromInstrument(value(2, 10), now: 1.00).toDevice.last, show(1, "8%"))
        XCTAssertEqual(driver.fromInstrument(value(2, 20), now: 1.02).toDevice, [.knob(1, position: ArturiaRotoDriver.position(forValue: 20))])
        XCTAssertEqual(driver.fromInstrument(value(2, 30), now: 1.04).toDevice, [.knob(1, position: ArturiaRotoDriver.position(forValue: 30))])
        XCTAssertTrue(driver.tick(now: 1.06).isEmpty)
        XCTAssertEqual(driver.tick(now: 1.09).toDevice, [show(1, "24%")], "the last value, 1/12 s after the first text")
        XCTAssertTrue(driver.tick(now: 1.2).isEmpty)
        // Another knob has its own limit.
        XCTAssertEqual(driver.fromInstrument(value(3, 127), now: 1.21).toDevice.last, show(2, "100%"))
    }

    func testPaging() {
        var driver = driverInPluginMode()
        _ = driver.fromInstrument(value(8, 86), now: 1)
        let second = driver.fromDevice(.message(.macroPage(1)), now: 2)
        XCTAssertEqual(second.toDevice, [learn(1, "Volume", ArturiaRotoDriver.position(forValue: 86)),
                                         .knob(0, position: ArturiaRotoDriver.position(forValue: 86))])
        XCTAssertEqual(driver.page, 1)
        // Knob 1 is now the volume: control change 17.
        XCTAssertEqual(driver.fromDevice(.control(.knob(0, position: 0)), now: 3).toInstrument, [[0xB0, 17, 0]])
        // Item 1 is on the other page now.
        XCTAssertTrue(driver.fromInstrument(value(1, 5), now: 4).isEmpty)
        let first = driver.fromDevice(.message(.macroPage(0)), now: 5)
        XCTAssertEqual(first.toDevice.count, 9, "eight LEARN PARAMs and the one known position")
        XCTAssertEqual(first.toDevice.first, learn(1, "Macro 1", ArturiaRotoDriver.position(forValue: 5)))
        // A page number past the last shows the last; the page is kept across MIX mode.
        _ = driver.fromDevice(.message(.macroPage(7)), now: 6)
        XCTAssertEqual(driver.page, 1)
        _ = driver.fromDevice(.message(.singleTrackMode(controlPage: 0)), now: 7)
        let back = driver.fromDevice(.message(.pluginMode), now: 8)
        XCTAssertEqual(Array(back.toDevice.prefix(5)), pluginList("Arturia", page: 1))
        XCTAssertEqual(back.toDevice.count, 7)
    }

    func testTextRenamesThePluginAndNamesThePreset() {
        var driver = driverInPluginMode()
        let output = driver.fromInstrument(text("Pigments", "*Hang Me Some Me"), now: 1)
        XCTAssertEqual(output.toDevice, pluginList("Pigments") + [.message(.currentTrackName("Hang Me Some Me"))])
        XCTAssertEqual(driver.presetName, "Hang Me Some Me")
        // The instrument has been seen to send the text twice: nothing the second time.
        XCTAssertTrue(driver.fromInstrument(text("Pigments", "*Hang Me Some Me"), now: 1.02).isEmpty)
        // A new preset: the name only.
        XCTAssertEqual(driver.fromInstrument(text("Pigments", "Welcome"), now: 2).toDevice, [.message(.currentTrackName("Welcome"))])
        // A long name is cut to 12 characters.
        XCTAssertEqual(driver.fromInstrument(text("Augmented STRINGS", "Welcome"), now: 3).toDevice, pluginList("Augmented ST"))
        XCTAssertEqual(driver.pluginName, "Augmented ST")
        // Coming back to PLUGIN mode sends the names again.
        _ = driver.fromDevice(.message(.singleTrackMode(controlPage: 0)), now: 4)
        let back = driver.fromDevice(.message(.pluginMode), now: 5).toDevice
        XCTAssertEqual(Array(back.prefix(5)), pluginList("Augmented ST"))
        XCTAssertEqual(back[5], .message(.currentTrackName("Welcome")))
    }

    func testInstrumentBytesSplitAcrossCalls() {
        var driver = driverInPluginMode()
        let message = value(2, 127)
        XCTAssertTrue(driver.fromInstrument(Array(message.prefix(5)), now: 1).isEmpty)
        XCTAssertEqual(driver.fromInstrument(Array(message.dropFirst(5)), now: 1).toDevice.first, rename(2, "Macro 2"))
    }
}
