import XCTest
@testable import ArturiaRotoDriver
import RotoControl
import ArturiaControl

/// The instrument's messages below are written from the layouts in docs/ARTURIA.md, section 3. The
/// driver uses the KeyLab mkII's profile unless a test says otherwise: items 1–4 are macros 1–4,
/// 5–8 the four parameters, and 9 the volume.
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

    /// The text a KeyLab mkII is sent after a control change: a name, a value text, and field 4.
    private func controlText(_ name: String, _ valueText: String, controller: UInt8, value: UInt8) -> [UInt8] {
        var bytes: [UInt8] = [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x04, 0x00, 0x60]
        bytes += [0x01] + Array(name.utf8) + [0x00]
        bytes += [0x02] + Array(valueText.utf8) + [0x00]
        bytes += [0x03, 0x00, 0x04, 0x63, controller, value, 0x3B, 0x00, 0xF7]
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
        let output = driver.fromInstrument(value(5, 74), now: 1)
        // Item 5 is knob 5 (Param 1): the name without "?", the position, and the value's text.
        XCTAssertEqual(output.toDevice, [rename(5, "Param 1"), .knob(4, position: ArturiaRotoDriver.position(forValue: 74)), show(4, "58%")])
        XCTAssertEqual(output.toInstrument, [], "a value the instrument reported is not sent back to it")
        // A second value: no name again.
        XCTAssertEqual(driver.fromInstrument(value(5, 0), now: 2).toDevice, [.knob(4, position: 0), show(4, "0%")])
        // An item on the other page is only kept.
        XCTAssertTrue(driver.fromInstrument(value(9, 86), now: 3).isEmpty)
        XCTAssertEqual(driver.value(forItem: 9), 86)
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
        _ = driver.fromInstrument(value(9, 86), now: 1)
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

    func testTheFirstKeyLabsProfileNumbersItemsItsOwnWay() {
        var driver = ArturiaRotoDriver(profile: .keyLab)
        XCTAssertEqual(driver.pages[0][4], ArturiaRotoControl(controller: 93, item: 9, name: "Param 1"))
        XCTAssertEqual(driver.pages[1][0], ArturiaRotoControl(controller: 17, item: 8, name: "Volume"))
        _ = driver.fromDevice(.message(.pluginMode), now: 0)
        XCTAssertEqual(driver.fromInstrument(value(9, 74), now: 1).toDevice.first, rename(5, "Param 1"))
        XCTAssertEqual(driver.fromDevice(.control(.knob(4, position: 0)), now: 2).toInstrument, [[0xB0, 93, 0]])
    }

    func testControlTextNamesTheKnobAndShowsTheInstrumentsValueText() {
        var driver = driverInPluginMode()
        // The knob is turned: control change 93 = 80 goes to the instrument, with a percentage,
        // since the instrument has sent no text yet.
        let turned = driver.fromDevice(.control(.knob(4, position: ArturiaRotoDriver.position(forValue: 80))), now: 1.0)
        XCTAssertEqual(turned.toInstrument, [[0xB0, 93, 80]])
        XCTAssertEqual(turned.toDevice, [rename(5, "Param 1"), show(4, "63%")])
        // The instrument answers with the name and its value text: the knob is renamed and shows
        // the text; the value is already known, so the knob is not moved.
        let answer = controlText("F1 Cutoff", "1448 Hz", controller: 93, value: 80)
        XCTAssertEqual(driver.fromInstrument(answer, now: 1.1).toDevice, [rename(5, "F1 Cutoff"), show(4, "1448 Hz")])
        XCTAssertEqual(driver.name(forItem: 5), "F1 Cutoff")
        XCTAssertTrue(driver.instrumentSendsText)
        // The same text twice more, as the instrument sends it: nothing.
        XCTAssertTrue(driver.fromInstrument(answer + answer, now: 1.2).isEmpty)
        // From now on a turn waits for the instrument's text.
        let again = driver.fromDevice(.control(.knob(4, position: ArturiaRotoDriver.position(forValue: 90))), now: 2.0)
        XCTAssertEqual(again.toInstrument, [[0xB0, 93, 90]])
        XCTAssertEqual(again.toDevice, [])
        XCTAssertEqual(driver.fromInstrument(controlText("F1 Cutoff", "2018 Hz", controller: 93, value: 90), now: 2.03).toDevice,
                       [show(4, "2018 Hz")])
        XCTAssertTrue(driver.tick(now: 2.3).isEmpty, "the text came: no percentage")
        // A turn the instrument doesn't answer shows a percentage after 0.2 s.
        _ = driver.fromDevice(.control(.knob(4, position: 0)), now: 3.0)
        XCTAssertTrue(driver.tick(now: 3.1).isEmpty)
        XCTAssertEqual(driver.tick(now: 3.21).toDevice, [show(4, "0%")])
        // LEARN PARAM carries the instrument's name.
        let page = driver.fromDevice(.message(.macroPage(0)), now: 4).toDevice
        XCTAssertEqual(page[4], learn(5, "F1 Cutoff", 0))
    }

    func testControlTextFromElsewhereMovesTheKnob() {
        var driver = driverInPluginMode()
        // A control change the driver didn't send (e.g., from another controller on the port).
        let output = driver.fromInstrument(controlText("Color", "0.236", controller: 74, value: 30), now: 1)
        XCTAssertEqual(output.toDevice, [rename(1, "Color"), .knob(0, position: ArturiaRotoDriver.position(forValue: 30)),
                                         show(0, "0.236")])
        // Another value, with a known value before it: renamed first, then moved.
        let next = driver.fromInstrument(controlText("Tone", "0.5", controller: 74, value: 64), now: 2)
        XCTAssertEqual(next.toDevice, [rename(1, "Tone"), .knob(0, position: ArturiaRotoDriver.position(forValue: 64)), show(0, "0.5")])
    }

    func testANewPresetForgetsTheNames() {
        var driver = driverInPluginMode()
        _ = driver.fromInstrument(text("Analog Lab", "*Fiber Lines"), now: 0.5)
        _ = driver.fromDevice(.control(.knob(0, position: ArturiaRotoDriver.position(forValue: 30))), now: 1)
        _ = driver.fromInstrument(controlText("Color", "0.236", controller: 74, value: 30), now: 1.03)
        XCTAssertEqual(driver.name(forItem: 1), "Color")
        // The same preset's text again (sent 2 s after a control text): the name stays.
        XCTAssertEqual(driver.fromInstrument(text("Analog Lab", "*Fiber Lines"), now: 3).toDevice, [])
        XCTAssertEqual(driver.name(forItem: 1), "Color")
        // Another preset: the knob goes back to the driver's name.
        let next = driver.fromInstrument(text("Analog Lab", "*00 ZENNY 1"), now: 4).toDevice
        XCTAssertEqual(next, [rename(1, "Macro 1"), .message(.currentTrackName("00 ZENNY 1"))])
        XCTAssertNil(driver.name(forItem: 1))
    }

    func testALateAnswerWhileTheKnobTurnsIsNotTakenForAChange() {
        var driver = driverInPluginMode()
        _ = driver.fromInstrument(controlText("Brightness", "0.528", controller: 74, value: 67), now: 0.5)
        // The knob sends 75, then 74; the instrument's answer to 75 comes after the 74 was sent.
        _ = driver.fromDevice(.control(.knob(0, position: ArturiaRotoDriver.position(forValue: 75))), now: 1.00)
        XCTAssertEqual(driver.fromDevice(.control(.knob(0, position: ArturiaRotoDriver.position(forValue: 74))), now: 1.02).toInstrument,
                       [[0xB0, 74, 74]])
        XCTAssertTrue(driver.fromInstrument(controlText("Brightness", "0.591", controller: 74, value: 75), now: 1.04).isEmpty)
        XCTAssertEqual(driver.value(forItem: 1), 74)
        XCTAssertEqual(driver.fromInstrument(controlText("Brightness", "0.583", controller: 74, value: 74), now: 1.07).toDevice,
                       [show(0, "0.583")])
        // Let go: the knob is not moved.
        XCTAssertTrue(driver.tick(now: 1.5).isEmpty)
    }

    func testAHeldBackTextWaitsForTheInstrumentsText() {
        var driver = driverInPluginMode()
        _ = driver.fromInstrument(controlText("Brightness", "0.480", controller: 74, value: 61), now: 1.00)
        // A second text within 1/12 s is held back.
        _ = driver.fromDevice(.control(.knob(0, position: ArturiaRotoDriver.position(forValue: 62))), now: 1.01)
        XCTAssertTrue(driver.fromInstrument(controlText("Brightness", "0.488", controller: 74, value: 62), now: 1.03).isEmpty)
        // The knob moves on to 60 before the held-back text is due: no percentage at the tick.
        _ = driver.fromDevice(.control(.knob(0, position: ArturiaRotoDriver.position(forValue: 60))), now: 1.05)
        XCTAssertTrue(driver.tick(now: 1.09).isEmpty)
        XCTAssertEqual(driver.fromInstrument(controlText("Brightness", "0.472", controller: 74, value: 60), now: 1.10).toDevice,
                       [show(0, "0.472")])
    }

    func testPigmentsKeepsItsNamesAcrossPresets() {
        var driver = driverInPluginMode()
        _ = driver.fromInstrument(text("Pigments", "*Hanging Threads"), now: 0.5)
        _ = driver.fromInstrument(controlText("F1 Cutoff", "1448 Hz", controller: 93, value: 80), now: 1)
        XCTAssertEqual(driver.fromInstrument(text("Pigments", "*Welcome"), now: 2).toDevice, [.message(.currentTrackName("Welcome"))])
        XCTAssertEqual(driver.name(forItem: 5), "F1 Cutoff")
        // Analog Lab V's text names the preset's instrument: a change drops the names.
        _ = driver.fromInstrument(text("Prophet-VS", "*00 ZENNY 1"), now: 4)
        XCTAssertNil(driver.name(forItem: 5))
    }

    /// A light's message from the instrument.
    private func light(_ item: UInt8, _ value: UInt8) -> [UInt8] {
        [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x02, 0x00, 0x10, item, value, 0xF7]
    }

    func testNamesFromFilesShowUntilTheInstrumentSendsBetter() {
        var driver = driverInPluginMode()
        // Parameter names, by control change: knobs 5 and 6 of the page are renamed ("?" stays
        // while the values are unknown); the volume is on the other page.
        let named = driver.setParameterNames([93: "F1 Cutoff", 18: "F1 Resonance", 17: "Master Volume", 7: "Not in the profile"])
        XCTAssertEqual(named.toDevice, [rename(5, "F1 Cutoff?"), rename(6, "F1 Resonance?")])
        // The preset's labels for the macros; an empty or missing label keeps the default.
        let labeled = driver.setPresetLabels(["Timbre", "", nil, "Delay"])
        XCTAssertEqual(labeled.toDevice, [rename(1, "Timbre?"), rename(4, "Delay?")])
        // The same again changes nothing.
        XCTAssertTrue(driver.setPresetLabels(["Timbre", "", nil, "Delay"]).isEmpty)
        // Pigments answers a turn of knob 1 with its fixed name, "Macro 1": the label stays.
        _ = driver.fromDevice(.control(.knob(0, position: ArturiaRotoDriver.position(forValue: 60))), now: 1)
        let fixed = driver.fromInstrument(controlText("Macro 1", "0.472", controller: 74, value: 60), now: 1.2)
        XCTAssertEqual(fixed.toDevice, [show(0, "0.472")])
        // A name that says more than the default wins over the label (Analog Lab V's).
        XCTAssertEqual(driver.fromInstrument(controlText("Density", "0.472", controller: 77, value: 60), now: 2).toDevice.first,
                       rename(4, "Density"))
        // LEARN PARAM carries the names shown.
        let page = driver.fromDevice(.message(.macroPage(0)), now: 3).toDevice
        XCTAssertEqual(page[0], learn(1, "Timbre", ArturiaRotoDriver.position(forValue: 60)))
        XCTAssertEqual(page[4], learn(5, "F1 Cutoff?", 0))
        _ = driver.fromInstrument(value(9, 86), now: 4)
        XCTAssertEqual(driver.fromDevice(.message(.macroPage(1)), now: 5).toDevice.first,
                       learn(1, "Master Volume", ArturiaRotoDriver.position(forValue: 86)))
        XCTAssertEqual(driver.presetValues.macros, [60, nil, nil, 60])
        XCTAssertEqual(driver.presetValues.volume, 86)
    }

    func testANewPresetDropsItsLabelsAndKeepsParameterNames() {
        var driver = driverInPluginMode()
        _ = driver.fromInstrument(text("Pigments", "*Hanging Threads"), now: 0.5)
        _ = driver.setParameterNames([93: "F1 Cutoff"])
        _ = driver.setPresetLabels(["Timbre", "Time", "Inharmonicity", "Delay"])
        XCTAssertEqual(driver.instrumentName, "Pigments")
        XCTAssertEqual(driver.presetKind, "Bells")
        let next = driver.fromInstrument(text("Pigments", "*Welcome"), now: 2).toDevice
        XCTAssertEqual(next, [rename(1, "Macro 1?"), rename(2, "Macro 2?"), rename(3, "Macro 3?"), rename(4, "Macro 4?"),
                              .message(.currentTrackName("Welcome"))])
        // Outside PLUGIN mode nothing is sent, and the names are there on coming back.
        _ = driver.fromDevice(.message(.singleTrackMode(controlPage: 0)), now: 3)
        XCTAssertTrue(driver.setPresetLabels(["Timbre", "Time", "Unison", "Reverb"]).isEmpty)
        let back = driver.fromDevice(.message(.pluginMode), now: 4).toDevice
        XCTAssertEqual(back[6], learn(1, "Timbre?", 0))
        XCTAssertEqual(back[10], learn(5, "F1 Cutoff?", 0))
    }

    func testAnalogLabIsKnownByItsTabLights() {
        var driver = ArturiaRotoDriver()
        _ = driver.fromInstrument(light(24, 127) + light(34, 0), now: 0)
        XCTAssertFalse(driver.hostIsAnalogLab, "Pigments lights these too")
        _ = driver.fromInstrument(light(31, 127), now: 1)
        XCTAssertTrue(driver.hostIsAnalogLab)
    }

    // MARK: The KeyLab mk3's format, asking, and a relayed keyboard

    private func mk3Value(_ item: UInt8, _ value: UInt8, id: UInt8 = 0x0D) -> [UInt8] {
        [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x00, id, 0x00, item, 0x01, value, 0x00, 0xF7]
    }

    private func mk3Preset(_ name: String, _ kind: String, picture: UInt8 = 45, id: UInt8 = 0x0D) -> [UInt8] {
        [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x00, id, 0x04, 0x10, 0x00] + Array(name.utf8) + [0x00, 0x01, 0x00, 0x00, 0x03]
            + Array(kind.utf8) + [0x00, 0x04, 0x01, 0x00, 0x05, 0x5D, 0x5D, 0x5D, 0x00, 0x06, picture, 0x00, 0xF7]
    }

    private func mk3Screen(_ name: String, _ valueText: String, value: UInt8, id: UInt8 = 0x0D) -> [UInt8] {
        [0xF0, 0x00, 0x20, 0x6B, 0x7F, 0x42, 0x00, id, 0x04, 0x1C, 0x00] + Array(valueText.utf8) + [0x00, 0x01]
            + Array(name.utf8) + [0x00, 0x02, value, 0x00, 0x03, 0x01, 0x00, 0x04, 0x01, 0x5D, 0x7C, 0x00, 0xF7]
    }

    private func mk3DriverInPluginMode(asks: Bool = false) -> ArturiaRotoDriver {
        var driver = ArturiaRotoDriver(profile: .keyLabMk3)
        driver.asksForNames = asks
        _ = driver.fromDevice(.message(.pluginMode), now: 0)
        return driver
    }

    func testTheMk3sFormat() {
        var driver = mk3DriverInPluginMode()
        XCTAssertEqual(driver.pages[0][0], ArturiaRotoControl(controller: 74, item: 0, name: "Macro 1"))
        XCTAssertEqual(driver.pages[1][0], ArturiaRotoControl(controller: 17, item: 8, name: "Volume"))
        // A value, then the preset: the instrument is known by the preset screen's picture.
        XCTAssertEqual(driver.fromInstrument(mk3Value(4, 64), now: 1).toDevice,
                       [rename(5, "Param 1"), .knob(4, position: ArturiaRotoDriver.position(forValue: 64)), show(4, "50%")])
        let preset = driver.fromInstrument(mk3Preset("Hang Me Some Melodies*", "Bells"), now: 2).toDevice
        XCTAssertEqual(driver.instrumentName, "Pigments")
        XCTAssertEqual(driver.presetName, "Hang Me Some Melodies")
        XCTAssertEqual(driver.presetKind, "Bells")
        XCTAssertFalse(driver.hostIsAnalogLab)
        XCTAssertEqual(preset.last, .message(.currentTrackName("Hang Me Some Melodies")))
        // A turn: the control change to the instrument, and the value for a keyboard's knob.
        let turned = driver.fromDevice(.control(.knob(4, position: ArturiaRotoDriver.position(forValue: 80))), now: 3)
        XCTAssertEqual(turned.toInstrument, [[0xB0, 93, 80]])
        XCTAssertEqual(turned.toKeyboard, [mk3Value(4, 80)])
        // The answer doesn't say which control: it is the last change with that value.
        XCTAssertEqual(driver.fromInstrument(mk3Screen("F1 Cutoff", "1448 Hz", value: 80), now: 3.2).toDevice,
                       [rename(5, "F1 Cutoff"), show(4, "1448 Hz")])
        // A screen for a value nothing sent is left alone, as is one that comes a second late.
        XCTAssertTrue(driver.fromInstrument(mk3Screen("Other", "1", value: 12), now: 3.3).isEmpty)
        XCTAssertTrue(driver.fromInstrument(mk3Screen("Late", "2", value: 80), now: 4.5).isEmpty)
        XCTAssertEqual(driver.name(forItem: 4), "F1 Cutoff")
        // Analog Lab V: its id.
        _ = driver.fromInstrument(mk3Preset("Fiber Lines", "Poly Lead", picture: 22, id: 1), now: 5)
        XCTAssertTrue(driver.hostIsAnalogLab)
        XCTAssertEqual(driver.instrumentName, "Analog Lab")
    }

    func testAskingForNames() {
        var driver = mk3DriverInPluginMode(asks: true)
        _ = driver.fromInstrument(mk3Value(0, 90) + mk3Value(1, 64), now: 1)
        // Not before the delay.
        XCTAssertTrue(driver.tick(now: 1.2).isEmpty)
        // Knob 1's value again, then nothing more until it is answered or 0.4 s have passed.
        XCTAssertEqual(driver.tick(now: 1.31).toInstrument, [[0xB0, 74, 90]])
        XCTAssertTrue(driver.tick(now: 1.33).isEmpty)
        // The answer names the knob, and shows no value text.
        XCTAssertEqual(driver.fromInstrument(mk3Screen("Color", "0.709", value: 90), now: 1.35).toDevice, [rename(1, "Color")])
        XCTAssertTrue(driver.fromInstrument(mk3Screen("Color", "0.709", value: 90) + mk3Screen("Color", "0.709", value: 90), now: 1.4).isEmpty)
        // Knob 2 next, once the answer's copies have had 0.2 s; unanswered, it is given up after
        // 0.4 s and not asked again.
        XCTAssertTrue(driver.tick(now: 1.42).isEmpty)
        XCTAssertEqual(driver.tick(now: 1.56).toInstrument, [[0xB0, 71, 64]])
        XCTAssertTrue(driver.tick(now: 1.8).isEmpty)
        XCTAssertTrue(driver.tick(now: 1.97).isEmpty)
        XCTAssertTrue(driver.tick(now: 3).isEmpty)
        // A new preset drops the names and sets the asking off again; a knob being turned puts it off.
        _ = driver.fromInstrument(mk3Preset("One", "Pad", picture: 22, id: 1), now: 4)
        _ = driver.fromInstrument(mk3Preset("Two", "Pad", picture: 22, id: 1), now: 5)
        XCTAssertNil(driver.name(forItem: 0))
        _ = driver.fromDevice(.control(.knob(7, position: 0)), now: 5.3)
        XCTAssertTrue(driver.tick(now: 5.4).toInstrument.isEmpty)
        XCTAssertEqual(driver.tick(now: 5.9).toInstrument, [[0xB0, 74, 90]])
        // Turned off, nothing is asked.
        var quiet = mk3DriverInPluginMode(asks: false)
        _ = quiet.fromInstrument(mk3Value(0, 90), now: 1)
        XCTAssertTrue(quiet.tick(now: 2).isEmpty)
    }

    func testAskingUnderTheMkIIsProfile() {
        var driver = driverInPluginMode()
        driver.asksForNames = true
        _ = driver.fromDevice(.message(.macroPage(0)), now: 0)
        _ = driver.fromInstrument(value(1, 90), now: 1)
        XCTAssertEqual(driver.tick(now: 1.31).toInstrument, [[0xB0, 74, 90]])
        XCTAssertEqual(driver.fromInstrument(controlText("Color", "0.709", controller: 74, value: 90), now: 1.35).toDevice, [rename(1, "Color")])
        XCTAssertTrue(driver.tick(now: 2).isEmpty)
    }

    func testARelayedKeyboardsKnobMovesTheRotoControls() {
        var driver = mk3DriverInPluginMode()
        // Notes and other bytes are left alone; a control change of the profile is a new value.
        XCTAssertTrue(driver.fromKeyboard([0x90, 60, 100, 0x80, 60, 0], now: 1).isEmpty)
        XCTAssertTrue(driver.fromKeyboard([0xB0, 1, 64], now: 1.1).isEmpty)
        XCTAssertEqual(driver.fromKeyboard([0xB0, 74, 40], now: 2).toDevice,
                       [rename(1, "Macro 1"), .knob(0, position: ArturiaRotoDriver.position(forValue: 40)), show(0, "31%")])
        // The instrument's answer to the keyboard's change names the Roto-Control's knob too.
        XCTAssertEqual(driver.fromInstrument(mk3Screen("Timbre", "0.315", value: 40), now: 2.2).toDevice,
                       [rename(1, "Timbre"), show(0, "0.315")])
        // A touch on the keyboard sends the same value again: nothing moves.
        XCTAssertTrue(driver.fromKeyboard([0xB0, 74, 40], now: 3).isEmpty)
    }

    func testAKeyboardTurnWaitsForTextAndLateAnswersDontMoveTheKnob() {
        var driver = mk3DriverInPluginMode()
        _ = driver.fromKeyboard([0xB0, 74, 89], now: 1)
        _ = driver.fromInstrument(mk3Screen("Macro 1", "0.701", value: 89), now: 1.05)
        // From now on the instrument sends text: a keyboard step shows no percentage.
        XCTAssertEqual(driver.fromKeyboard([0xB0, 74, 91], now: 2).toDevice,
                       [.knob(0, position: ArturiaRotoDriver.position(forValue: 91))])
        XCTAssertEqual(driver.fromKeyboard([0xB0, 74, 92], now: 2.07).toDevice,
                       [.knob(0, position: ArturiaRotoDriver.position(forValue: 92))])
        // The answer to 91 comes after 92 was sent: the knob stays at 92.
        XCTAssertTrue(driver.fromInstrument(mk3Screen("Macro 1", "0.717", value: 91), now: 2.08).isEmpty)
        XCTAssertEqual(driver.value(forItem: 0), 92)
        XCTAssertEqual(driver.fromInstrument(mk3Screen("Macro 1", "0.724", value: 92), now: 2.11).toDevice, [show(0, "0.724")])
        // No percentage later either.
        XCTAssertTrue(driver.tick(now: 2.5).isEmpty)
    }

    func testAnAnswersCopiesAreNotTakenForTheNextAnswer() {
        var driver = mk3DriverInPluginMode(asks: true)
        _ = driver.fromInstrument(mk3Preset("01 Fingapikka", "Keys", picture: 31, id: 1), now: 0.5)
        XCTAssertEqual(driver.instrumentName, "Analog Lab")
        _ = driver.fromInstrument(mk3Value(2, 0, id: 1) + mk3Value(3, 0, id: 1), now: 1)
        XCTAssertEqual(driver.tick(now: 1.31).toInstrument, [[0xB0, 76, 0]])
        let screen = mk3Screen("Macro 3", "0.00", value: 0, id: 1)
        // "Macro 3" is the default name already, and an asked answer shows no value text.
        XCTAssertTrue(driver.fromInstrument(screen, now: 1.33).isEmpty)
        // The next knob waits for the copies, which change nothing.
        XCTAssertTrue(driver.tick(now: 1.35).isEmpty)
        XCTAssertTrue(driver.fromInstrument(screen, now: 1.37).isEmpty)
        XCTAssertTrue(driver.fromInstrument(screen, now: 1.40).isEmpty)
        XCTAssertEqual(driver.tick(now: 1.54).toInstrument, [[0xB0, 77, 0]])
        XCTAssertEqual(driver.fromInstrument(mk3Screen("Reverb Volume", "-70.0 dB", value: 0, id: 1), now: 1.58).toDevice,
                       [rename(4, "Reverb Volume")])
        XCTAssertEqual(driver.name(forItem: 2), "Macro 3")
        XCTAssertEqual(driver.name(forItem: 3), "Reverb Volume")
    }

    func testAnalogLabsNamesAreDroppedAtAPresetChangeAfterPigments() {
        var driver = mk3DriverInPluginMode()
        _ = driver.fromInstrument(mk3Preset("Welcome", "Template"), now: 1)
        XCTAssertEqual(driver.instrumentName, "Pigments")
        // The same driver, now hearing Analog Lab V (id 1).
        _ = driver.fromKeyboard([0xB0, 18, 10], now: 2)
        _ = driver.fromInstrument(mk3Screen("Phaser Mix", "8 %", value: 10, id: 1), now: 2.05)
        _ = driver.fromInstrument(mk3Preset("Blue Hopper", "Evolving Pad", picture: 35, id: 1), now: 3)
        XCTAssertEqual(driver.instrumentName, "Analog Lab")
        _ = driver.fromKeyboard([0xB0, 18, 12], now: 4)
        _ = driver.fromInstrument(mk3Screen("Chorus Mix", "9 %", value: 12, id: 1), now: 4.05)
        _ = driver.fromInstrument(mk3Preset("Fever Keys", "Lofi Keys", picture: 35, id: 1), now: 5)
        XCTAssertNil(driver.name(forItem: 5))
    }
}
