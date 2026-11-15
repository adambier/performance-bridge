import XCTest
@testable import ArturiaControl

/// The value and text messages are ones Pigments sent in test 1 of docs/ARTURIA.md; the others
/// are made up.
final class ArturiaKeyLabTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    func testValueMessage() {
        XCTAssertEqual(ArturiaInstrumentMessage.parse(bytes("F0 00 20 6B 7F 42 02 00 00 01 66 F7")), .value(item: 1, value: 0x66))
        XCTAssertEqual(ArturiaInstrumentMessage.parse(bytes("F0 00 20 6B 7F 42 02 00 00 09 7F F7")), .value(item: 9, value: 127))
    }

    func testTextMessage() {
        let message = bytes("F0 00 20 6B 7F 42 04 00 60 01 50 69 67 6D 65 6E 74 73 00 02 2A 57 65 6C 63 6F 6D 65 00 03 54 65 6D 70 6C 61 74 65 00 04 00 F7")
        XCTAssertEqual(ArturiaInstrumentMessage.parse(message), .text([
            ArturiaTextField(tag: 1, text: "Pigments"),
            ArturiaTextField(tag: 2, text: "*Welcome"),
            ArturiaTextField(tag: 3, text: "Template"),
            ArturiaTextField(tag: 4, text: ""),
        ]))
    }

    func testOtherAndForeignMessages() {
        // A light's message has 10 where a value's has 00.
        XCTAssertEqual(ArturiaInstrumentMessage.parse(bytes("F0 00 20 6B 7F 42 02 00 10 18 7F F7")), .light(item: 24, value: 127))
        let other = bytes("F0 00 20 6B 7F 42 02 00 20 18 7F F7")
        XCTAssertEqual(ArturiaInstrumentMessage.parse(other), .other(other))
        // The Roto-Control's DAW STARTED is not Arturia's.
        XCTAssertNil(ArturiaInstrumentMessage.parse(bytes("F0 00 22 03 02 0A 01 F7")))
        XCTAssertNil(ArturiaInstrumentMessage.parse(bytes("B0 4A 64")))
        XCTAssertNil(ArturiaInstrumentMessage.parse([]))
        // A text message cut short still gives the fields it holds.
        XCTAssertEqual(ArturiaInstrumentMessage.parse(bytes("F0 00 20 6B 7F 42 04 00 60 01 50 F7")), .text([ArturiaTextField(tag: 1, text: "P")]))
    }

    func testAssemblerJoinsPieces() {
        var assembler = ArturiaSysExAssembler()
        let message = bytes("F0 00 20 6B 7F 42 02 00 00 01 66 F7")
        XCTAssertEqual(assembler.feed(message[0..<5]), [])
        XCTAssertEqual(assembler.feed(message[5...]), [message])
        // Two messages in one piece, a control change between them, and a clock byte inside one.
        let second = bytes("F0 00 20 6B 7F 42 02 00 00 02 00 F7")
        let withClock = Array(second[0..<6]) + [0xF8] + Array(second[6...])
        XCTAssertEqual(assembler.feed(message + bytes("B0 4A 64") + withClock), [message, second])
        // A message cut off by a status byte is dropped, and a stray F7 gives nothing.
        XCTAssertEqual(assembler.feed(bytes("F0 00 20 B0 4A 64 F7")), [])
    }

    func testProfile() {
        XCTAssertEqual(ArturiaKeyLabProfile.keyLab.item(forController: 74), 1)
        XCTAssertEqual(ArturiaKeyLabProfile.keyLab.controller(forItem: 8), 17)
        XCTAssertNil(ArturiaKeyLabProfile.keyLab.item(forController: 1))
        XCTAssertEqual(ArturiaKeyLabProfile.keyLab.controlChange(item: 1, value: 100), bytes("B0 4A 64"))
        XCTAssertEqual(ArturiaKeyLabProfile.keyLab.controlChange(item: 48, value: 0, channel: 16), [0xBF, 7, 0])
        XCTAssertNil(ArturiaKeyLabProfile.keyLab.controlChange(item: 11, value: 0))
        XCTAssertNil(ArturiaKeyLabProfile.keyLab.controlChange(item: 1, value: 128))
        XCTAssertEqual(Set(ArturiaKeyLabProfile.keyLab.controls.map(\.item)).count, 11)
        XCTAssertEqual(Set(ArturiaKeyLabProfile.keyLab.controls.map(\.controller)).count, 11)
    }

    func testMkIIProfile() {
        let profile = ArturiaKeyLabProfile.keyLabMkII
        XCTAssertEqual(profile.item(forController: 74), 1)
        XCTAssertEqual(profile.item(forController: 93), 5)
        XCTAssertEqual(profile.item(forController: 17), 9)
        XCTAssertNil(profile.item(forController: 7))
        XCTAssertEqual(profile.controlChange(item: 9, value: 64), bytes("B0 11 40"))
        XCTAssertEqual(ArturiaKeyLabProfile.forPortName("KeyLab mkII 61"), profile)
        XCTAssertEqual(ArturiaKeyLabProfile.forPortName("KeyLab mkII 49 MIDI"), profile)
        XCTAssertEqual(ArturiaKeyLabProfile.forPortName("KeyLab mkII 88 (1)"), profile)
        XCTAssertEqual(ArturiaKeyLabProfile.forPortName("KeyLab 61"), .keyLab)
        XCTAssertEqual(ArturiaKeyLabProfile.forPortName("KeyLab 61 mk3 MIDI"), .keyLabMk3)
        XCTAssertNil(ArturiaKeyLabProfile.forPortName("KeyLab 61 mk3 DAW"))
        XCTAssertEqual(ArturiaKeyLabProfile.keyLabMk3.item(forController: 74), 0)
        XCTAssertEqual(ArturiaKeyLabProfile.keyLabMk3.controlChange(item: 8, value: 5), bytes("B0 11 05"))
    }

    func testControlText() {
        // Analog Lab V, test 4: "Color", "0.236", after control change 74 = 30.
        let color = bytes("F0 00 20 6B 7F 42 04 00 60 01 43 6F 6C 6F 72 00 02 30 2E 32 33 36 00 03 00 04 63 4A 1E 3B 00 F7")
        XCTAssertEqual(ArturiaInstrumentMessage.parse(color),
                       .controlText(ArturiaControlText(name: "Color", valueText: "0.236", controller: 74, value: 30)))
        // Pigments, test 4: "F1 Cutoff", "1448 Hz", after control change 93 = 80.
        let cutoff = bytes("F0 00 20 6B 7F 42 04 00 60 01 46 31 20 43 75 74 6F 66 66 00 02 31 34 34 38 20 48 7A 00 03 00 04 63 5D 50 3B 00 F7")
        XCTAssertEqual(ArturiaInstrumentMessage.parse(cutoff),
                       .controlText(ArturiaControlText(name: "F1 Cutoff", valueText: "1448 Hz", controller: 93, value: 80)))
        // A value of 0 (not seen) is read as a value, not as the end of the field.
        let zero = bytes("F0 00 20 6B 7F 42 04 00 60 01 41 00 02 30 00 03 00 04 63 4A 00 3B 00 F7")
        XCTAssertEqual(ArturiaInstrumentMessage.parse(zero),
                       .controlText(ArturiaControlText(name: "A", valueText: "0", controller: 74, value: 0)))
    }

    func testMk3Messages() {
        // Seen from Pigments (id 13) and Analog Lab V (id 1): docs/ARTURIA.md, tests 5, 6, and 8.
        XCTAssertEqual(ArturiaMk3Message.parse(bytes("F0 00 20 6B 7F 42 00 0D 05 01 F7")), .connect(true, id: 13))
        XCTAssertEqual(ArturiaMk3Message.parse(bytes("F0 00 20 6B 7F 42 00 01 05 00 F7")), .connect(false, id: 1))
        XCTAssertEqual(ArturiaMk3Message.parse(bytes("F0 00 20 6B 7F 42 00 01 00 08 01 6D 00 F7")),
                       .property(item: 8, index: 1, value: 109, id: 1))
        XCTAssertEqual(ArturiaMk3Message.parse(bytes("F0 00 20 6B 7F 42 00 01 00 33 02 00 00 F7")),
                       .property(item: 51, index: 2, value: 0, id: 1))
        // "Welcome*", "Template", picture 45.
        let welcome = bytes("F0 00 20 6B 7F 42 00 0D 04 10 00 57 65 6C 63 6F 6D 65 2A 00 01 00 00 03 54 65 6D 70 6C 61 74 65 00 04 01 00 05 5D 5D 5D 00 06 2D 00 F7")
        XCTAssertEqual(ArturiaMk3Message.parse(welcome), .preset(name: "Welcome", isChanged: true, kind: "Template", picture: 45, id: 13))
        // "Fiber Lines", "Poly Lead", picture 22, not changed.
        let fiber = bytes("F0 00 20 6B 7F 42 00 01 04 10 00 46 69 62 65 72 20 4C 69 6E 65 73 00 01 00 00 03 50 6F 6C 79 20 4C 65 61 64 00 04 01 00 05 5D 5D 5D 00 06 16 00 F7")
        XCTAssertEqual(ArturiaMk3Message.parse(fiber), .preset(name: "Fiber Lines", isChanged: false, kind: "Poly Lead", picture: 22, id: 1))
        // "0.551", "Color", value 70.
        let color = bytes("F0 00 20 6B 7F 42 00 01 04 1C 00 30 2E 35 35 31 00 01 43 6F 6C 6F 72 00 02 46 00 03 01 00 04 01 5D 7C 00 F7")
        XCTAssertEqual(ArturiaMk3Message.parse(color), .controlScreen(valueText: "0.551", name: "Color", value: 70, id: 1))
        // A value of 0 is a value, not the end of the field.
        let zero = bytes("F0 00 20 6B 7F 42 00 0D 04 1C 00 30 00 01 41 00 02 00 00 03 01 00 04 01 5D 7C 00 F7")
        XCTAssertEqual(ArturiaMk3Message.parse(zero), .controlScreen(valueText: "0", name: "A", value: 0, id: 13))
        // Other screens, and other formats.
        let button = bytes("F0 00 20 6B 7F 42 00 0D 04 02 00 0A 00 02 01 00 03 11 00 04 7F 7F 7F 00 F7")
        XCTAssertEqual(ArturiaMk3Message.parse(button), .other(button))
        XCTAssertNil(ArturiaMk3Message.parse(bytes("F0 00 20 6B 7F 42 02 00 00 01 3C F7")))
        XCTAssertNil(ArturiaMk3Message.parse(bytes("B0 4A 46")))
        XCTAssertEqual(ArturiaMk3Message.knobValue(item: 3, value: 70, id: 13), bytes("F0 00 20 6B 7F 42 00 0D 00 03 01 46 00 F7"))
        XCTAssertEqual(ArturiaMk3Message.parse(ArturiaMk3Message.knobValue(item: 3, value: 70, id: 13)),
                       .property(item: 3, index: 1, value: 70, id: 13))
    }

    func testAWholeNameIsNotAPrefix() {
        XCTAssertTrue(ArturiaPresetMatch.name("Around The World Bass", matchesSent: "Around The World"))
        XCTAssertFalse(ArturiaPresetMatch.name("Around The World Bass", matchesSent: "Around The World", isWhole: true))
        XCTAssertTrue(ArturiaPresetMatch.name("Around The World", matchesSent: "Around The World", isWhole: true))
    }
}
