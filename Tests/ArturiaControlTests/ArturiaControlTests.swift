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
        // A light's message has 10 where a value's has 00 (read from the instrument's code, not seen).
        let light = bytes("F0 00 20 6B 7F 42 02 00 10 18 7F F7")
        XCTAssertEqual(ArturiaInstrumentMessage.parse(light), .other(light))
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
        XCTAssertNil(ArturiaKeyLabProfile.forPortName("KeyLab 61 mk3 MIDI"))
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
}
