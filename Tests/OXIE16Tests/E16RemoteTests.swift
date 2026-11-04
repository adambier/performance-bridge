import XCTest
@testable import OXIE16

final class E16RemoteTests: XCTestCase {
    /// The packing example from schwung's field notes: FF 00 80 7F 01 FE 55 AA → 25 7F 00 00 7F 01 7E 55 01 2A.
    func testPackingMatchesTheKnownExample() {
        let raw: [UInt8] = [0xFF, 0x00, 0x80, 0x7F, 0x01, 0xFE, 0x55, 0xAA]
        XCTAssertEqual(E16Outgoing.pack(raw), [0x25, 0x7F, 0x00, 0x00, 0x7F, 0x01, 0x7E, 0x55, 0x01, 0x2A])
        XCTAssertEqual(E16Outgoing.unpack(E16Outgoing.pack(raw)), raw)
    }

    func testPackingNeverSetsBitSeven() {
        let raw = (0..<1024).map { UInt8($0 & 0xFF) }
        let packed = E16Outgoing.pack(raw)
        XCTAssertEqual(packed.count, 1024 + 147)  // one MSB byte per 7, the last group of 2
        XCTAssertTrue(packed.allSatisfy { $0 < 0x80 })
        XCTAssertEqual(E16Outgoing.unpack(packed), raw)
    }

    func testEnterAndExitAreTheSheetsExamples() {
        XCTAssertEqual(E16Outgoing.enterRemoteMode, [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x55, 0xF7])
        XCTAssertEqual(E16Outgoing.exitRemoteMode, [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x00, 0xF7])
    }

    func testRingMessage() {
        let ring = E16Ring(red: 127, green: 40, blue: 0, amount: 0.5, bipolar: true)
        XCTAssertEqual(ring.amount14, 8192)
        let bytes = E16Outgoing.rings([(encoder: 3, ring: ring)])
        // Header, ID, then the packed 7-byte chunk (its MSB byte is 0) and F7.
        XCTAssertEqual(bytes, [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x04,
                               0x00, 3, 127, 40, 0, 0x40, 0x00, 1, 0xF7])
        XCTAssertEqual(E16Outgoing.rings([(encoder: 16, ring: ring)]), [], "an encoder out of range sends nothing")
        XCTAssertEqual(E16Ring(red: 0, green: 0, blue: 0, amount: 2).amount14, 16383)
        XCTAssertEqual(E16Ring(red: 0, green: 0, blue: 0, amount: .nan).amount14, 0)
    }

    func testLabelsAreEightyBytesCutAndPadded() {
        let bytes = E16Outgoing.labels(title: "A title that is far too long", labels: ["AN 1", "Longer", "é"])
        XCTAssertEqual(bytes.count, 8 + 80 + 12 + 1)  // header+ID, 80 raw bytes become 92 packed, F7
        let raw = E16Outgoing.unpack(Array(bytes[8..<(bytes.count - 1)]))
        XCTAssertEqual(String(decoding: raw[0..<16], as: UTF8.self), "A title that is ")
        XCTAssertEqual(String(decoding: raw[16..<20], as: UTF8.self), "AN 1")
        XCTAssertEqual(String(decoding: raw[20..<24], as: UTF8.self), "Long")
        XCTAssertEqual(String(decoding: raw[24..<28], as: UTF8.self), "?   ")
        XCTAssertEqual(String(decoding: raw[28..<32], as: UTF8.self), "    ")
    }

    func testParserDecodesTurnsPushesShiftAndTheAck() {
        var parser = E16Parser()
        var events = parser.feed([0xB0, 1, 0x01, 0xB0, 16, 0x7F, 0xB0, 5, 0x08, 0xB0, 5, 0x78])
        XCTAssertEqual(events, [.turned(encoder: 0, delta: 1), .turned(encoder: 15, delta: -1),
                                .turned(encoder: 4, delta: 8), .turned(encoder: 4, delta: -8)])
        events = parser.feed([0x90, 2, 0x7F, 0x80, 2, 0x00, 0x90, 16, 0x7F, 0x90, 16, 0x00])
        XCTAssertEqual(events, [.pushed(encoder: 2, down: true), .pushed(encoder: 2, down: false),
                                .shift(down: true), .shift(down: false)])
        events = parser.feed([0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x06, 0x53, 0xF7])
        XCTAssertEqual(events, [.remoteEntered])
    }

    func testParserTakesSysExInPiecesAndRunningStatus() {
        var parser = E16Parser()
        XCTAssertEqual(parser.feed([0xF0, 0x00, 0x21, 0x5B]), [])
        XCTAssertEqual(parser.feed([0x02, 0x01, 0x06]), [])
        XCTAssertEqual(parser.feed([0x53, 0xF7, 0xB0, 1, 0x02]), [.remoteEntered, .turned(encoder: 0, delta: 2)])
        XCTAssertEqual(parser.feed([2, 0x7E]), [.turned(encoder: 1, delta: -2)], "running status")
        XCTAssertEqual(parser.feed([0xF8, 0xB0, 3, 0x01]), [.turned(encoder: 2, delta: 1)], "real-time bytes are skipped")
        XCTAssertEqual(parser.feed([0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01, 0x53, 0x00, 0x05, 0xF7]),
                       [.sysEx([0x00, 0x21, 0x5B, 0x02, 0x01, 0x53, 0x00, 0x05])])
        XCTAssertEqual(parser.feed([0xB0, 0, 0x01]), [.other([0xB0, 0, 0x01])], "CC 0 is not an encoder")
    }
}
