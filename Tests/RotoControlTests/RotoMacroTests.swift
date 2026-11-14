import XCTest
@testable import RotoControl

/// SHA-1, the hashes taken from it, and the macro plugin's messages. The SHA-1 vectors are the
/// standard's; the expected hashes were computed with another SHA-1 implementation (Python's
/// hashlib). The message layouts follow docs/ROTO-CONTROL.md and a reading of Melbourne
/// Instruments' Bitwig integration.
final class RotoMacroTests: XCTestCase {
    private let head: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02]

    private func hexText(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    func testSHA1Vectors() {
        XCTAssertEqual(hexText(RotoSHA1.digest("")), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(hexText(RotoSHA1.digest("abc")), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(hexText(RotoSHA1.digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")),
                       "84983e441c3bd26ebaae4aa1f95129e5e54670f1", "two blocks")
        XCTAssertEqual(hexText(RotoSHA1.digest([UInt8](repeating: 0x61, count: 1_000_000))),
                       "34aa973cd4c4daa4f61eeb2bdbad27316534016f", "a million a's")
        // Lengths around the padding boundary (55, 56, and 64 bytes).
        XCTAssertEqual(hexText(RotoSHA1.digest([UInt8](repeating: 0x61, count: 55))), "c1c8bbdc22796e28c0e15163d20899b65621d65a")
        XCTAssertEqual(hexText(RotoSHA1.digest([UInt8](repeating: 0x61, count: 56))), "c2db330f6083854c99d4b5bfb6e8f29f201be699")
        XCTAssertEqual(hexText(RotoSHA1.digest([UInt8](repeating: 0x61, count: 64))), "0098ba824b5c16427bd7a1122a5a442a25ec644d")
    }

    func testSHA1Hashes() {
        XCTAssertEqual(RotoHash.macroPlugin.bytes, [0x25, 0x68, 0x4B, 0x67, 0x0F, 0x1F, 0x77, 0x52])
        XCTAssertEqual(RotoHash.sha1(of: "MIMacroDefaultDevice", length: 8), RotoHash.macroPlugin)
        XCTAssertEqual(RotoHash.macroParameter(1).bytes, [0x11, 0x5A, 0x74, 0x3B, 0x1E, 0x5F])
        XCTAssertEqual(RotoHash.macroParameter(8).bytes, [0x77, 0x12, 0x6D, 0x54, 0x0B, 0x30])
        XCTAssertEqual(RotoHash.sha1(of: "abc", length: 4).bytes, [0x29, 0x19, 0x3E, 0x36], "each byte masked to 7 bits")
        XCTAssertEqual(RotoHash.sha1(of: "abc", length: 99).bytes.count, 20)
        XCTAssertEqual(RotoHash.sha1(of: "abc", length: -1).bytes, [])
        XCTAssertNotEqual(RotoHash.sha1(of: "Macro 1", length: 6), RotoHash.of("Macro 1", length: 6), "the FNV hash is unchanged")
    }

    func testMacroPluginDetails() {
        let details = RotoPluginDetails.macro(index: 0, name: "Macro Test", pages: 2)
        XCTAssertEqual(details.type, .macro)
        let name: [UInt8] = Array("Macro Test".utf8) + [0, 0, 0]
        var expected: [UInt8] = head + [0x0B, 0x05, 0x00, 0x25, 0x68, 0x4B, 0x67, 0x0F, 0x1F, 0x77, 0x52, 0x01]
        expected += name
        expected += [0x01, 0x02, 0xF7]
        XCTAssertEqual(RotoOutgoing.pluginDetails(details).bytes, expected)
        XCTAssertEqual(RotoOutgoing.dawSelectPlugin(index: 0, macroPage: 1, force: false).bytes,
                       head + [0x0B, 0x08, 0x00, 0x01, 0x00, 0xF7])
    }

    func testMacroLearnParameter() {
        let details = RotoParameterDetails.macro(3, name: "Drive", position: RotoFeedback.position(0.5))
        XCTAssertTrue(details.isMacro)
        XCTAssertEqual(details.index, 3)
        XCTAssertEqual(RotoFeedback.position(0.5), 8192)
        let hash = RotoHash.macroParameter(3).bytes
        XCTAssertEqual(hash.count, 6)
        let name: [UInt8] = Array("Drive".utf8) + [UInt8](repeating: 0, count: 8)
        // index (2), hash (6), macro 1, center 0, steps 0, position 8192 as 0x40 0x00, name (13).
        var learn: [UInt8] = head + [0x0B, 0x0A, 0x00, 0x03]
        learn += hash
        learn += [0x01, 0x00, 0x00, 0x40, 0x00]
        learn += name
        learn += [0xF7]
        XCTAssertEqual(RotoOutgoing.learnParameter(details).bytes, learn)
        var rename: [UInt8] = head + [0x0B, 0x0F, 0x00, 0x03]
        rename += hash
        rename += name
        rename += [0xF7]
        XCTAssertEqual(RotoOutgoing.mappedControlName(parameterIndex: 3, hash: .macroParameter(3), name: "Drive").bytes, rename)
    }

    func testMacroMessagesFromTheDevice() {
        XCTAssertEqual(RotoIncoming(sysEx: head + [0x0B, 0x10, 0x01, 0xF7]), .macroPage(1))
        let hash = RotoHash.macroParameter(2)
        var mapped: [UInt8] = head + [0x0B, 0x0B, 0x00, 0x02]
        mapped += hash.bytes
        mapped += [0x00, 0x01, 0x01, 0xF7]
        XCTAssertEqual(RotoIncoming(sysEx: mapped),
                       .controlMapped(RotoControlMapping(parameterIndex: 2, parameterHash: hash, kind: .knob, control: 1, isMacro: true)))
    }
}
