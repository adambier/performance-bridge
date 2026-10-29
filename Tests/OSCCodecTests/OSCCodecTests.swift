import XCTest
@testable import OSCCodec

final class OSCCodecTests: XCTestCase {
    /// The example from the OSC 1.0 specification: "/oscillator/4/frequency" with the float 440.0.
    func testSpecificationExampleFloat() throws {
        let message = OSCMessage("/oscillator/4/frequency", [.float(440)])
        let expected: [UInt8] = Array("/oscillator/4/frequency".utf8) + [0]
            + Array(",f".utf8) + [0, 0]
            + [0x43, 0xDC, 0x00, 0x00]
        XCTAssertEqual(message.encoded(), expected)
        XCTAssertEqual(try OSCPacket(decoding: expected), .message(message))
    }

    /// The second example from the OSC 1.0 specification: "/foo" with 1000, -1, "hello", 1.234, 5.678.
    func testSpecificationExampleMixed() throws {
        let message = OSCMessage("/foo", [.int(1000), .int(-1), .string("hello"), .float(1.234), .float(5.678)])
        let expected: [UInt8] = [
            0x2F, 0x66, 0x6F, 0x6F, 0, 0, 0, 0,
            0x2C, 0x69, 0x69, 0x73, 0x66, 0x66, 0, 0,
            0x00, 0x00, 0x03, 0xE8,
            0xFF, 0xFF, 0xFF, 0xFF,
            0x68, 0x65, 0x6C, 0x6C, 0x6F, 0, 0, 0,
            0x3F, 0x9D, 0xF3, 0xB6,
            0x40, 0xB5, 0xB2, 0x2D,
        ]
        XCTAssertEqual(message.encoded(), expected)
        XCTAssertEqual(try OSCPacket(decoding: expected), .message(message))
    }

    func testStringPaddingAtEveryLength() throws {
        for length in 0...9 {
            let text = String(repeating: "a", count: length)
            let message = OSCMessage("/s", [.string(text)])
            let bytes = message.encoded()
            XCTAssertEqual(bytes.count % 4, 0, "length \(length)")
            XCTAssertEqual(try OSCPacket(decoding: bytes), .message(message), "length \(length)")
        }
    }

    func testEveryArgumentTypeRoundTrips() throws {
        let message = OSCMessage("/all", [
            .int(-7), .float(-0.5), .string("TotalMix"), .blob([1, 2, 3, 4, 5]),
            .bool(true), .bool(false), .null, .int64(-1 << 40), .double(0.125),
        ])
        XCTAssertEqual(try OSCPacket(decoding: message.encoded()), .message(message))
    }

    func testNestedBundleRoundTripsAndFlattens() throws {
        let inner = OSCBundle(timeTag: 42, elements: [.message(OSCMessage("/b", [.float(2)]))])
        let outer = OSCBundle(elements: [.message(OSCMessage("/a", [.float(1)])), .bundle(inner), .message(OSCMessage("/c"))])
        let packet = OSCPacket.bundle(outer)
        let decoded = try OSCPacket(decoding: packet.encoded())
        XCTAssertEqual(decoded, packet)
        XCTAssertEqual(decoded.messages.map(\.address), ["/a", "/b", "/c"])
    }

    func testMessageWithoutTypeTagsHasNoArguments() throws {
        let bytes: [UInt8] = Array("/undo".utf8) + [0, 0, 0]
        XCTAssertEqual(try OSCPacket(decoding: bytes), .message(OSCMessage("/undo")))
    }

    func testMalformedInputThrows() {
        XCTAssertThrowsError(try OSCPacket(decoding: [UInt8]())) { XCTAssertEqual($0 as? OSCDecodeError, .truncated) }
        XCTAssertThrowsError(try OSCPacket(decoding: Array("hello".utf8))) { XCTAssertEqual($0 as? OSCDecodeError, .notOSC) }
        // A string with no terminator.
        XCTAssertThrowsError(try OSCPacket(decoding: Array("/abc".utf8))) { XCTAssertEqual($0 as? OSCDecodeError, .badString) }
        // A float announced but missing.
        let missing: [UInt8] = Array("/a".utf8) + [0, 0] + Array(",f".utf8) + [0, 0]
        XCTAssertThrowsError(try OSCPacket(decoding: missing)) { XCTAssertEqual($0 as? OSCDecodeError, .truncated) }
        // An unknown type tag.
        let unknown: [UInt8] = Array("/a".utf8) + [0, 0] + Array(",q".utf8) + [0, 0]
        XCTAssertThrowsError(try OSCPacket(decoding: unknown)) { XCTAssertEqual($0 as? OSCDecodeError, .unsupportedType("q")) }
        // A bundle element whose size runs past the end.
        let bundle: [UInt8] = Array("#bundle".utf8) + [0] + [0, 0, 0, 0, 0, 0, 0, 1] + [0, 0, 0, 16] + Array("/a".utf8) + [0, 0]
        XCTAssertThrowsError(try OSCPacket(decoding: bundle)) { XCTAssertEqual($0 as? OSCDecodeError, .truncated) }
    }

    func testNumericValueAcceptsEveryNumberForm() {
        XCTAssertEqual(OSCArgument.float(0.5).numericValue, 0.5)
        XCTAssertEqual(OSCArgument.int(1).numericValue, 1)
        XCTAssertEqual(OSCArgument.bool(true).numericValue, 1)
        XCTAssertEqual(OSCArgument.bool(false).numericValue, 0)
        XCTAssertNil(OSCArgument.string("1").numericValue)
    }

    func testAddressParts() {
        XCTAssertEqual(OSCMessage("/input/3/eq/band1gain").addressParts, ["input", "3", "eq", "band1gain"])
        XCTAssertEqual(OSCMessage("/undo").addressParts, ["undo"])
    }
}
