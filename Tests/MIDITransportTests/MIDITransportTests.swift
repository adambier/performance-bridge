import XCTest
@testable import MIDITransport

final class UniversalPacketsTests: XCTestCase {
    func testChannelMessages() {
        XCTAssertEqual(UniversalPackets.words(fromBytes: [0xBF, 12, 104]), [0x20BF_0C68])
        XCTAssertEqual(UniversalPackets.words(fromBytes: [0xC3, 5]), [0x20C3_0500])
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x20BF_0C68]), [0xBF, 12, 104])
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x20C3_0500]), [0xC3, 5])
        // A knob position, high CC then low CC, survives the round trip.
        let knob: [UInt8] = [0xBF, 12, 104, 0xBF, 44, 60]
        XCTAssertEqual(UniversalPackets.bytes(fromWords: UniversalPackets.words(fromBytes: knob)), knob)
    }

    func testSystemMessages() {
        XCTAssertEqual(UniversalPackets.words(fromBytes: [0xF8]), [0x10F8_0000])
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x10F8_0000]), [0xF8])
        XCTAssertEqual(UniversalPackets.words(fromBytes: [0xF2, 0x10, 0x20]), [0x10F2_1020])
    }

    func testShortSysEx() {
        // DAW STARTED: six data bytes, one complete packet.
        let message: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02, 0x0A, 0x01, 0xF7]
        let words = UniversalPackets.words(fromBytes: message)
        XCTAssertEqual(words, [0x3006_0022, 0x0302_0A01])
        XCTAssertEqual(UniversalPackets.bytes(fromWords: words), message)
    }

    func testLongSysExSplitsIntoStartContinueEnd() {
        let data = (0..<14).map { UInt8($0) }
        let message = [0xF0] + data + [0xF7]
        let words = UniversalPackets.words(fromBytes: message)
        XCTAssertEqual(words.count, 6)
        XCTAssertEqual(words[0] >> 16, 0x3016, "start, 6 bytes")
        XCTAssertEqual(words[2] >> 16, 0x3026, "continue, 6 bytes")
        XCTAssertEqual(words[4] >> 16, 0x3032, "end, 2 bytes")
        XCTAssertEqual(UniversalPackets.bytes(fromWords: words), message)
        // Split across calls, the bytes still join into the same stream.
        XCTAssertEqual(UniversalPackets.bytes(fromWords: Array(words[0..<2])), [0xF0, 0, 1, 2, 3, 4, 5])
        XCTAssertEqual(UniversalPackets.bytes(fromWords: Array(words[4..<6])), [12, 13, 0xF7])
    }

    func testEmptySysExAndExactMultiples() {
        XCTAssertEqual(UniversalPackets.words(fromBytes: [0xF0, 0xF7]), [0x3000_0000, 0])
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x3000_0000, 0]), [0xF0, 0xF7])
        let twelve = [0xF0] + [UInt8](repeating: 0x11, count: 12) + [0xF7]
        let words = UniversalPackets.words(fromBytes: twelve)
        XCTAssertEqual(words.count, 4)
        XCTAssertEqual(words[2] >> 16, 0x3036, "end packet carries the last six bytes")
        XCTAssertEqual(UniversalPackets.bytes(fromWords: words), twelve)
    }

    func testMixedStreamAndSkippedTypes() {
        let stream: [UInt8] = [0xBF, 20, 127, 0xF0, 0x01, 0x02, 0xF7, 0xBF, 52, 0]
        XCTAssertEqual(UniversalPackets.bytes(fromWords: UniversalPackets.words(fromBytes: stream)), stream)
        // A utility (type 0) word and a MIDI 2.0 channel voice packet (type 4, two words) are skipped.
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x0000_0000, 0x40B0_0C00, 0xFFFF_FFFF, 0x20BF_1400]), [0xBF, 20, 0])
    }

    func testMalformedInput() {
        XCTAssertEqual(UniversalPackets.words(fromBytes: [0x01, 0x02]), [], "data bytes without a status")
        XCTAssertEqual(UniversalPackets.words(fromBytes: [0xBF, 12]), [], "a message cut short")
        XCTAssertEqual(UniversalPackets.words(fromBytes: [0xF0, 0x01]), [], "SysEx without F7")
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x3006_0022]), [], "a SysEx packet missing its second word")
    }

    func testWordCounts() {
        XCTAssertEqual((0...15).map { UniversalPackets.wordCount(forType: $0) },
                       [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4])
    }
}

final class MIDIEndpointMatchTests: XCTestCase {
    private let endpoints = [
        MIDIEndpointInfo(name: "Roto-Control", uniqueID: 1),
        MIDIEndpointInfo(name: "Launch Control XL 3 DAW Out", uniqueID: 2),
        MIDIEndpointInfo(name: "Launch Control XL 3 MIDI Out", uniqueID: 3),
    ]

    func testMatching() {
        XCTAssertEqual(MIDIEndpointInfo.match("roto-control", in: endpoints)?.uniqueID, 1)
        XCTAssertEqual(MIDIEndpointInfo.match("Roto", in: endpoints)?.uniqueID, 1)
        XCTAssertEqual(MIDIEndpointInfo.match("DAW", in: endpoints)?.uniqueID, 2)
        XCTAssertNil(MIDIEndpointInfo.match("Launch Control", in: endpoints), "two partial matches")
        XCTAssertNil(MIDIEndpointInfo.match("Faderport", in: endpoints))
    }

    #if !canImport(CoreMIDI)
    func testPlaceholderThrows() {
        XCTAssertEqual(MIDIConnection.sources(), [])
        XCTAssertThrowsError(try MIDIConnection(clientName: "test", sourceName: "x", destinationName: "x") { _ in }) {
            XCTAssertEqual($0 as? MIDIConnectionError, .unsupportedPlatform)
        }
    }
    #endif
}
