import XCTest
@testable import MIDITransport
import RotoControl

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

    func testReservedAndMisplacedValuesAreSkipped() {
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x3042_0102, 0]), [], "reserved SysEx status")
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x10F0_0000]), [], "F0 is not a system message word")
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x20F8_0000]), [], "F8 is not a channel message")
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x10F3_0500, 0x10F1_2200]), [0xF3, 5, 0xF1, 0x22])
        XCTAssertEqual(UniversalPackets.bytes(fromWords: [0x10F2_1020]), [0xF2, 0x10, 0x20])
    }

    func testPackets() {
        let words: [UInt32] = [0x20BF_0C68, 0x3016_0001, 0x0203_0405, 0x3032_0607, 0, 0x10F8_0000, 0x3016]
        XCTAssertEqual(UniversalPackets.packets(words).map(Array.init),
                       [[0x20BF_0C68], [0x3016_0001, 0x0203_0405], [0x3032_0607, 0], [0x10F8_0000], [0x3016]])
    }

    func testEveryRotoMessageSurvivesTheRoundTrip() {
        let details = RotoTrackDetails(index: 130, name: "Analog 1/2", colorScheme: 40, grouped: true)
        let messages: [RotoOutgoing] = [
            .dawStarted, .pingResponse(.bitwig), .trackCount(300), .firstTrack(128),
            .trackDetails(details, immediate: false), .trackDetailsEnd, .selectTrack(details),
            .showValue(.knob, control: 3, text: "-12.1 dB"), .meterThresholds(yellow: 87, red: 113),
            .sendNames(start: 8, names: ["Main", "Phones 1", "Phones 2"]),
            .trackColor(index: 2, RotoColor(red: 255, green: 128, blue: 0)),
        ]
        for message in messages {
            let bytes = message.bytes
            XCTAssertEqual(UniversalPackets.bytes(fromWords: UniversalPackets.words(fromBytes: bytes)), bytes, "\(message)")
        }
    }

    func testSplitSysExWithRealTimeBetweenPacketsDecodes() {
        // As CoreMIDI may deliver it: a SysEx split over several callbacks, with a clock between.
        let ping = RotoOutgoing.sendNames(start: 0, names: ["Main"]).bytes
        let packets = UniversalPackets.packets(UniversalPackets.words(fromBytes: ping))
        var decoder = RotoInputDecoder()
        var inputs: [RotoInput] = []
        for (number, packet) in packets.enumerated() {
            inputs += decoder.feed(UniversalPackets.bytes(fromWords: Array(packet)))
            if number == 1 { inputs += decoder.feed(UniversalPackets.bytes(fromWords: [0x10F8_0000])) }
        }
        XCTAssertEqual(inputs, [.message(.other(group: 0x0C, command: 0x08, data: Array(ping[7..<(ping.count - 1)])))])
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
        let withDuplicates = endpoints + [MIDIEndpointInfo(name: "Roto-Control 2", uniqueID: 4)]
        XCTAssertEqual(MIDIEndpointInfo.match("Roto-Control", in: withDuplicates)?.uniqueID, 1, "an exact name wins over partial matches")
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
