import XCTest
@testable import RotoControl

/// Byte sequences below are written from the layouts in docs/ROTO-CONTROL.md.
final class RotoSysExTests: XCTestCase {
    private let head: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02]

    func testFrameAndUnframe() {
        XCTAssertEqual(RotoSysEx.frame(.general, 0x01), head + [0x0A, 0x01, 0xF7])
        let framed = RotoSysEx.frame(.mix, 0x0B, [87, 113])
        let unframed = RotoSysEx.unframe(framed)
        XCTAssertEqual(unframed?.group, 0x0C)
        XCTAssertEqual(unframed?.command, 0x0B)
        XCTAssertEqual(unframed?.data, [87, 113])
    }

    func testUnframeRejectsOtherMessages() {
        XCTAssertNil(RotoSysEx.unframe([0xF0, 0x00, 0x20, 0x29, 0x02, 0x0A, 0x01, 0xF7]))
        XCTAssertNil(RotoSysEx.unframe(head + [0x0A, 0x01]))
        XCTAssertNil(RotoSysEx.unframe(head + [0x0A, 0xF7]))
        XCTAssertNil(RotoSysEx.unframe(head + [0x0A, 0x01, 0x00]), "long enough, but no F7")
    }

    func testFourteenBitNumbers() {
        XCTAssertEqual(RotoSysEx.encode14(0), [0, 0])
        XCTAssertEqual(RotoSysEx.encode14(8), [0, 8])
        XCTAssertEqual(RotoSysEx.encode14(200), [1, 72])
        XCTAssertEqual(RotoSysEx.encode14(16383), [0x7F, 0x7F])
        XCTAssertEqual(RotoSysEx.encode14(20000), [0x7F, 0x7F])
        XCTAssertEqual(RotoSysEx.encode14(-3), [0, 0])
        for value in [0, 1, 127, 128, 4095, 13372, 16383] {
            let bytes = RotoSysEx.encode14(value)
            XCTAssertEqual(RotoSysEx.decode14(bytes[0], bytes[1]), value)
        }
    }

    func testColorComponents() {
        XCTAssertEqual(RotoSysEx.encodeColorComponent(0x00), [0, 0x00])
        XCTAssertEqual(RotoSysEx.encodeColorComponent(0x7F), [0, 0x7F])
        XCTAssertEqual(RotoSysEx.encodeColorComponent(0x80), [1, 0x00])
        XCTAssertEqual(RotoSysEx.encodeColorComponent(0xFF), [1, 0x7F])
    }

    func testNames() {
        let short = RotoSysEx.encodeName("Main")
        XCTAssertEqual(short.count, 13)
        XCTAssertEqual(Array(short.prefix(5)), [0x4D, 0x61, 0x69, 0x6E, 0])
        XCTAssertEqual(RotoSysEx.decodeName(short), "Main")

        let long = RotoSysEx.encodeName("Analog 1/2 long name")
        XCTAssertEqual(long.count, 13)
        XCTAssertEqual(long.last, 0)
        XCTAssertEqual(RotoSysEx.decodeName(long), "Analog 1/2 l")

        XCTAssertEqual(RotoSysEx.decodeName(RotoSysEx.encodeName("Café\tB")), "Caf??B")
        XCTAssertEqual(RotoSysEx.encodeName(""), [UInt8](repeating: 0, count: 13))
    }
}

final class RotoMessageTests: XCTestCase {
    private let head: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02]

    private func incoming(_ body: [UInt8]) -> RotoIncoming? {
        RotoIncoming(sysEx: head + body + [0xF7])
    }

    func testHandshakeMessages() {
        XCTAssertEqual(incoming([0x0A, 0x02]), .pingDAW)
        XCTAssertEqual(incoming([0x0A, 0x0C]), .connected)
        XCTAssertEqual(RotoOutgoing.dawStarted.bytes, head + [0x0A, 0x01, 0xF7])
        XCTAssertEqual(RotoOutgoing.pingResponse(.ableton).bytes, head + [0x0A, 0x03, 0x01, 0xF7])
        XCTAssertEqual(RotoOutgoing.pingResponse(.bitwig).bytes, head + [0x0A, 0x03, 0x02, 0xF7])
        XCTAssertEqual(RotoOutgoing.pingResponse(.logic).bytes, head + [0x0A, 0x03, 0x03, 0xF7])
    }

    func testIncomingMixMessages() {
        XCTAssertEqual(incoming([0x0A, 0x06, 0x01, 0x00]), .setFirstTrack(128))
        XCTAssertEqual(incoming([0x0A, 0x09, 0x00, 0x0B]), .selectTrack(11))
        XCTAssertEqual(incoming([0x0C, 0x01, 0x01, 0x02, 0x01, 0x03]),
                       .allTracksMode(RotoAllTracksMode(trackSet: .masterReturn, knobMode: .send,
                                                        switchMode: .solo, sendIndex: 3)))
        XCTAssertEqual(incoming([0x0C, 0x02, 0x08]), .singleTrackMode(controlPage: 8))
        XCTAssertEqual(incoming([0x0C, 0x05, 0x00]), .trackSet(.audio))
        XCTAssertEqual(incoming([0x0C, 0x06, 0x00, 0x05]), .toggleTrackGrouping(5))
        XCTAssertEqual(incoming([0x0C, 0x07, 0x0E]), .requestSendNames(sendIndex: 14))
        XCTAssertEqual(incoming([0x0A, 0x0A]), .requestTransportStatus)
        XCTAssertEqual(incoming([0x0A, 0x14]), .pageLeft)
        XCTAssertEqual(incoming([0x0A, 0x15]), .pageRight)
        XCTAssertEqual(incoming([0x0B, 0x01]), .pluginMode)
    }

    func testIncomingVersions() {
        XCTAssertEqual(incoming([0x0A, 0x0E, 3, 2, 0, 0x61, 0x62, 0x63, 0x31, 0x32, 0x33, 0x34]),
                       .firmwareVersion(major: 3, minor: 2, patch: 0, commit: "abc1234"))
        XCTAssertEqual(incoming([0x0A, 0x10, 1, 6]), .sysExAPIVersion(major: 1, minor: 6))
    }

    func testMalformedOrUnknownMessagesBecomeOther() {
        XCTAssertEqual(incoming([0x0C, 0x01, 0x05, 0x00, 0x00, 0x00]),
                       .other(group: 0x0C, command: 0x01, data: [0x05, 0x00, 0x00, 0x00]))
        XCTAssertEqual(incoming([0x0A, 0x06, 0x01]), .other(group: 0x0A, command: 0x06, data: [0x01]))
        XCTAssertEqual(incoming([0x0B, 0x1E, 0x00, 0x02]), .other(group: 0x0B, command: 0x1E, data: [0x00, 0x02]))
        XCTAssertNil(RotoIncoming(sysEx: [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]))
    }

    func testTrackMessages() {
        XCTAssertEqual(RotoOutgoing.trackCount(16).bytes, head + [0x0A, 0x04, 0x00, 0x10, 0xF7])
        XCTAssertEqual(RotoOutgoing.firstTrack(136).bytes, head + [0x0A, 0x05, 0x01, 0x08, 0xF7])
        let details = RotoTrackDetails(index: 9, name: "Phones", colorScheme: 21, grouped: true)
        let expected = head + [0x0A, 0x07, 0x00, 0x09] + RotoSysEx.encodeName("Phones") + [21, 1, 0xF7]
        XCTAssertEqual(RotoOutgoing.trackDetails(details, immediate: false).bytes, expected)
        var immediate = expected
        immediate[6] = 0x11
        XCTAssertEqual(RotoOutgoing.trackDetails(details, immediate: true).bytes, immediate)
        XCTAssertEqual(RotoOutgoing.trackDetailsEnd.bytes, head + [0x0A, 0x08, 0xF7])
        XCTAssertEqual(RotoOutgoing.resetTrackDetails(3).bytes, head + [0x0A, 0x12, 0x00, 0x03, 0xF7])
        var selected = expected
        selected[5] = 0x0C
        selected[6] = 0x04
        XCTAssertEqual(RotoOutgoing.selectTrack(details).bytes, selected)
    }

    func testColorMessages() {
        let color = RotoColor(red: 0xFF, green: 0x80, blue: 0x10)
        XCTAssertEqual(RotoOutgoing.trackColor(index: 2, color).bytes,
                       head + [0x0A, 0x13, 0x00, 0x02, 1, 0x7F, 1, 0x00, 0, 0x10, 0xF7])
        XCTAssertEqual(RotoOutgoing.currentTrackColor(color).bytes,
                       head + [0x0A, 0x17, 1, 0x7F, 1, 0x00, 0, 0x10, 0xF7])
        XCTAssertEqual(RotoOutgoing.selectFocusTrack(index: 130, color).bytes,
                       head + [0x0C, 0x0A, 0x01, 0x02, 1, 0x7F, 1, 0x00, 0, 0x10, 0xF7])
    }

    func testValuesAndStatus() {
        XCTAssertEqual(RotoOutgoing.showValue(.knob, control: 4, text: "-12.1 dB").bytes,
                       head + [0x0A, 0x18, 0x00, 0x04] + RotoSysEx.encodeName("-12.1 dB") + [0xF7])
        XCTAssertEqual(RotoOutgoing.showValue(.switch, control: 9, text: "On").bytes[7...8], [0x01, 0x07])
        var status = RotoTransportStatus()
        status.play = true
        status.loop = true
        XCTAssertEqual(RotoOutgoing.transportStatus(status).bytes,
                       head + [0x0A, 0x0B, 1, 0, 0, 0, 1, 0, 0, 0, 0xF7])
        XCTAssertEqual(RotoOutgoing.currentTrackName("Main").bytes.count, 5 + 2 + 13 + 1)
        XCTAssertEqual(RotoOutgoing.requestFirmwareVersion.bytes, head + [0x0A, 0x0D, 0xF7])
        XCTAssertEqual(RotoOutgoing.requestSysExAPIVersion.bytes, head + [0x0A, 0x0F, 0xF7])
    }

    func testMixMessages() {
        XCTAssertEqual(RotoOutgoing.sendCount(4).bytes, head + [0x0C, 0x03, 0x04, 0xF7])
        XCTAssertEqual(RotoOutgoing.refreshMixMode.bytes, head + [0x0C, 0x09, 0xF7])
        XCTAssertEqual(RotoOutgoing.meterThresholds(yellow: 87, red: 113).bytes, head + [0x0C, 0x0B, 87, 113, 0xF7])
        XCTAssertEqual(RotoOutgoing.meterStates([true, false, true]).bytes,
                       head + [0x0C, 0x0C, 1, 0, 1, 0, 0, 0, 0, 0, 0xF7])

        let names = RotoOutgoing.sendNames(start: 8, names: ["AES 1/2", "Phones"]).bytes
        XCTAssertEqual(names.count, 5 + 2 + 1 + 8 * 13 + 1)
        XCTAssertEqual(names[7], 8)
        XCTAssertEqual(RotoSysEx.decodeName(names[8..<21]), "AES 1/2")
        XCTAssertEqual(RotoSysEx.decodeName(names[21..<34]), "Phones")
        XCTAssertEqual(Array(names[34..<112]), [UInt8](repeating: 0, count: 78))
    }

    func testSendNameBlocks() {
        // The SysEx doc's examples for all-tracks mode and REQUEST SEND TRACK NAMES.
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forSendIndex: 0x00), 0x00)
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forSendIndex: 0x07), 0x00)
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forSendIndex: 0x08), 0x08)
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forSendIndex: 0x14), 0x10)
        // Its examples for single-track mode, with pages as multiples of 8.
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forControlPage: 0x00, numbering: .multiplesOf8), 0x00)
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forControlPage: 0x08, numbering: .multiplesOf8), 0x06)
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forControlPage: 0x10, numbering: .multiplesOf8), 0x0E)
        // The same layout with pages numbered 0, 1, 2, as Ableton and Bitwig read them.
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forControlPage: 0, numbering: .pageNumbers), 0)
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forControlPage: 1, numbering: .pageNumbers), 6)
        XCTAssertEqual(RotoOutgoing.sendNamesStart(forControlPage: 2, numbering: .pageNumbers), 14)
    }

    func testDataBytesStaySevenBit() {
        for message in [RotoOutgoing.trackDetails(RotoTrackDetails(index: 16383, name: "ÿÿÿ", colorScheme: 255), immediate: false),
                        .trackColor(index: 99999, RotoColor(red: 255, green: 255, blue: 255)),
                        .meterThresholds(yellow: 200, red: 255),
                        .sendNames(start: 300, names: ["x"]),
                        .showValue(.knob, control: -1, text: "é")] {
            let bytes = message.bytes
            XCTAssertTrue(bytes.dropFirst().dropLast().allSatisfy { $0 < 0x80 }, "\(message)")
        }
    }
}

final class RotoMIDIParserTests: XCTestCase {
    func testSysExAcrossChunks() {
        var parser = RotoMIDIParser()
        XCTAssertEqual(parser.feed([0xF0, 0x00, 0x22]), [])
        XCTAssertEqual(parser.feed([0x03, 0x02, 0x0A]), [])
        XCTAssertEqual(parser.feed([0x02, 0xF7, 0xBF, 0x14, 0x7F]),
                       [.sysEx([0xF0, 0x00, 0x22, 0x03, 0x02, 0x0A, 0x02, 0xF7]),
                        .controlChange(channel: 15, controller: 20, value: 127)])
    }

    func testRunningStatusAndRealTime() {
        var parser = RotoMIDIParser()
        XCTAssertEqual(parser.feed([0xBF, 0x0C, 0x40, 0xF8, 0x2C, 0x00, 0x34]),
                       [.controlChange(channel: 15, controller: 12, value: 64),
                        .controlChange(channel: 15, controller: 44, value: 0)])
        XCTAssertEqual(parser.feed([0x7F]), [.controlChange(channel: 15, controller: 52, value: 127)])
        XCTAssertEqual(parser.feed([0xF0, 0x01, 0xFE, 0x02, 0xF7]), [.sysEx([0xF0, 0x01, 0x02, 0xF7])])
    }

    func testOtherMessagesAndInterruptions() {
        var parser = RotoMIDIParser()
        XCTAssertEqual(parser.feed([0x90, 0x3C, 0x64, 0xC0, 0x05]), [.other([0x90, 0x3C, 0x64]), .other([0xC0, 0x05])])
        // A status byte inside SysEx drops the SysEx; the new message still parses.
        XCTAssertEqual(parser.feed([0xF0, 0x00, 0x22, 0xBF, 0x15, 0x00, 0xF7]),
                       [.controlChange(channel: 15, controller: 21, value: 0)])
        // Data after a system common message is skipped; running status does not survive it.
        XCTAssertEqual(parser.feed([0xF2, 0x10, 0x20, 0x30]), [])
        XCTAssertEqual(parser.feed([0xF7]), [])
        XCTAssertEqual(parser.feed([0x14, 0x7F]), [], "a surviving running status would make this a CC")
        XCTAssertEqual(parser.feed([0xBF, 0x14, 0x7F]), [.controlChange(channel: 15, controller: 20, value: 127)])
    }

    func testOverlongSysExIsDropped() {
        var parser = RotoMIDIParser()
        let long = [0xF0] + [UInt8](repeating: 0x01, count: RotoMIDIParser.maximumSysExLength + 10) + [0xF7]
        XCTAssertEqual(parser.feed(long), [])
        XCTAssertEqual(parser.feed([0xF0, 0x02, 0xF7]), [.sysEx([0xF0, 0x02, 0xF7])])
    }
}

final class RotoControlDecoderTests: XCTestCase {
    func testKnobsPairHighAndLow() {
        var decoder = RotoControlDecoder()
        XCTAssertNil(decoder.decode(channel: 15, controller: 44, value: 5), "low before any high is dropped")
        XCTAssertNil(decoder.decode(channel: 15, controller: 12, value: 0x68))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 44, value: 0x3C), .knob(0, position: 0x68 << 7 | 0x3C))
        // An unchanged high CC may be left out: the last one is kept.
        XCTAssertEqual(decoder.decode(channel: 15, controller: 44, value: 0x3D), .knob(0, position: 0x68 << 7 | 0x3D))
        XCTAssertNil(decoder.decode(channel: 15, controller: 19, value: 0x7F))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 51, value: 0x7F), .knob(7, position: 16383))
    }

    func testSwitchesTouchAndTransport() {
        var decoder = RotoControlDecoder()
        XCTAssertEqual(decoder.decode(channel: 15, controller: 20, value: 127), .switch(0, pressed: true))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 21, value: 64), .switch(1, pressed: true))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 21, value: 63), .switch(1, pressed: false))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 27, value: 0), .switch(7, pressed: false))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 28, value: 127), .transport(0, pressed: true))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 35, value: 0), .transport(7, pressed: false))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 52, value: 127), .touch(0, touched: true))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 59, value: 0), .touch(7, touched: false))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 64, value: 3), .levelToZeroDB(3))
    }

    func testOtherCCs() {
        var decoder = RotoControlDecoder()
        XCTAssertEqual(decoder.decode(channel: 0, controller: 12, value: 1), .otherCC(channel: 0, controller: 12, value: 1))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 64, value: 9), .otherCC(channel: 15, controller: 64, value: 9))
        XCTAssertEqual(decoder.decode(channel: 15, controller: 70, value: 1), .otherCC(channel: 15, controller: 70, value: 1))
    }
}

final class RotoFeedbackTests: XCTestCase {
    func testKnobPosition() {
        XCTAssertEqual(RotoFeedback.knob(0, position: 13372), [0xBF, 12, 104, 0xBF, 44, 60])
        XCTAssertEqual(RotoFeedback.knob(7, position: 99999), [0xBF, 19, 0x7F, 0xBF, 51, 0x7F])
    }

    func testSwitchLightsAndMeters() {
        XCTAssertEqual(RotoFeedback.switchLight(2, on: true), [0xBF, 22, 127])
        XCTAssertEqual(RotoFeedback.switchLight(2, on: false), [0xBF, 22, 0])
        XCTAssertEqual(RotoFeedback.meter(0, left: 90, right: 200), [0xBF, 65, 90, 0xBF, 66, 127])
        XCTAssertEqual(RotoFeedback.meter(7, left: 1, right: 2), [0xBF, 79, 1, 0xBF, 80, 2])
    }

    func testPositionAndFraction() {
        XCTAssertEqual(RotoFeedback.position(0), 0)
        XCTAssertEqual(RotoFeedback.position(1), 16383)
        XCTAssertEqual(RotoFeedback.position(0.5), 8192)
        XCTAssertEqual(RotoFeedback.position(-1), 0)
        // TotalMix's 0 dB fader position, step 836 of 1023.
        XCTAssertEqual(RotoFeedback.position(836.0 / 1023), 13388)
        XCTAssertEqual(RotoFeedback.fraction(16383), 1)
        XCTAssertEqual(RotoFeedback.fraction(0), 0)
        for position in stride(from: 0, through: 16383, by: 97) {
            XCTAssertEqual(RotoFeedback.position(RotoFeedback.fraction(position)), position)
        }
    }

    func testFeedbackDecodesAsTheSameKnob() {
        var parser = RotoMIDIParser()
        var decoder = RotoControlDecoder()
        let events = parser.feed(RotoFeedback.knob(3, position: 5000)).compactMap { message -> RotoControlEvent? in
            guard case .controlChange(let channel, let controller, let value) = message else { return nil }
            return decoder.decode(channel: channel, controller: controller, value: value)
        }
        XCTAssertEqual(events, [.knob(3, position: 5000)])
    }
}

final class RotoHandshakeTests: XCTestCase {
    func testHappyPath() {
        var handshake = RotoHandshake(hostType: .bitwig)
        XCTAssertEqual(handshake.state, .idle)
        XCTAssertEqual(handshake.start(), [.dawStarted])
        XCTAssertEqual(handshake.state, .waitingForPing)

        let ping = handshake.handle(.pingDAW)
        XCTAssertEqual(ping.reply, [.pingResponse(.bitwig)])
        XCTAssertFalse(ping.justConnected)
        XCTAssertEqual(handshake.state, .waitingForConnected)
        XCTAssertFalse(handshake.isConnected)

        let connected = handshake.handle(.connected)
        XCTAssertEqual(connected.reply, [])
        XCTAssertTrue(connected.justConnected)
        XCTAssertTrue(handshake.isConnected)
    }

    func testPingWithoutStartIsAnswered() {
        // The Roto-Control pings by itself when it is plugged in.
        var handshake = RotoHandshake(hostType: .ableton)
        XCTAssertEqual(handshake.handle(.pingDAW).reply, [.pingResponse(.ableton)])
        XCTAssertTrue(handshake.handle(.connected).justConnected)
    }

    func testStrayConnectedAndReconnect() {
        var handshake = RotoHandshake(hostType: .ableton)
        _ = handshake.start()
        XCTAssertFalse(handshake.handle(.connected).justConnected, "CONNECTED before any ping is ignored")
        XCTAssertEqual(handshake.state, .waitingForPing)

        _ = handshake.handle(.pingDAW)
        _ = handshake.handle(.connected)
        XCTAssertFalse(handshake.handle(.connected).justConnected, "a second CONNECTED changes nothing")
        XCTAssertTrue(handshake.isConnected)

        // A ping after CONNECTED: answered, and the handshake waits for CONNECTED again.
        XCTAssertEqual(handshake.handle(.pingDAW).reply, [.pingResponse(.ableton)])
        XCTAssertFalse(handshake.isConnected)
        XCTAssertTrue(handshake.handle(.connected).justConnected)
        XCTAssertEqual(handshake.handle(.selectTrack(2)).reply, [])

        // Restarting sends DAW STARTED again and drops the connection until the next ping.
        XCTAssertEqual(handshake.start(), [.dawStarted])
        XCTAssertFalse(handshake.isConnected)
        XCTAssertFalse(handshake.handle(.connected).justConnected)
    }

    func testInputDecoderCombinesBoth() {
        var decoder = RotoInputDecoder()
        let bytes: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02, 0x0A, 0x02, 0xF7,
                              0xBF, 0x0D, 0x01, 0x2D, 0x00,
                              0xF0, 0x7E, 0x00, 0xF7,
                              0x90, 0x3C, 0x40]
        XCTAssertEqual(decoder.feed(bytes), [.message(.pingDAW), .control(.knob(1, position: 128))])
    }
}

final class RotoPluginTests: XCTestCase {
    private let head: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02]

    private func incoming(_ body: [UInt8]) -> RotoIncoming? {
        RotoIncoming(sysEx: head + body + [0xF7])
    }

    func testHashes() {
        let a = RotoHash.of("Ch EQ", length: 8)
        XCTAssertEqual(a.bytes.count, 8)
        XCTAssertEqual(a, RotoHash.of("Ch EQ", length: 8), "stable")
        XCTAssertNotEqual(a, RotoHash.of("Ch Dynamics", length: 8))
        XCTAssertTrue(a.bytes.allSatisfy { $0 < 0x80 })
        XCTAssertEqual(RotoHash.of("x", length: 6).bytes.count, 6)
        XCTAssertEqual(RotoHash.of("x", length: 20).bytes.count, 9, "64 bits give at most nine 7-bit bytes")
        XCTAssertEqual(RotoHash(bytes: [0xFF, 0x80]).bytes, [0x7F, 0x00])
        XCTAssertEqual(RotoHash(bytes: [1, 2]).field(4), [1, 2, 0, 0])
        XCTAssertEqual(RotoHash(bytes: [1, 2, 3]).field(2), [1, 2])
    }

    func testIncomingPluginMessages() {
        // Observed in test 1: SET PLUGIN MODE with a data byte the SysEx doc does not list.
        XCTAssertEqual(incoming([0x0B, 0x01, 0x00]), .pluginMode)
        XCTAssertEqual(incoming([0x0B, 0x01]), .pluginMode)
        XCTAssertEqual(incoming([0x0B, 0x04, 0x08]), .setFirstPlugin(8))
        XCTAssertEqual(incoming([0x0B, 0x07, 0x02]), .selectPlugin(2))
        XCTAssertEqual(incoming([0x0B, 0x09, 0x01]), .learnMode(true))
        XCTAssertEqual(incoming([0x0B, 0x09, 0x00]), .learnMode(false))
        XCTAssertEqual(incoming([0x0B, 0x0B, 0x01, 0x02, 1, 2, 3, 4, 5, 6, 0x01, 0x05, 0x00]),
                       .controlMapped(RotoControlMapping(parameterIndex: 130, parameterHash: RotoHash(bytes: [1, 2, 3, 4, 5, 6]),
                                                         kind: .switch, control: 5, isMacro: false)))
        XCTAssertEqual(incoming([0x0B, 0x0C, 0x03, 0x00]), .pluginEnabled(3, false))
        XCTAssertEqual(incoming([0x0B, 0x0D, 0x01]), .pluginsLocked(true))
        XCTAssertEqual(incoming([0x0B, 0x10, 0x02]), .macroPage(2))
        XCTAssertEqual(incoming([0x0B, 0x11, 0x00, 0x07]), .controlLearned(.knob, control: 7))
        XCTAssertEqual(incoming([0x0B, 0x12]), .toggleRemotePage)
        // Short or invalid data falls back to .other.
        XCTAssertEqual(incoming([0x0B, 0x0B, 0x00, 0x01]), .other(group: 0x0B, command: 0x0B, data: [0x00, 0x01]))
        XCTAssertEqual(incoming([0x0B, 0x11, 0x05, 0x01]), .other(group: 0x0B, command: 0x11, data: [0x05, 0x01]))
        // Logic-only commands are not decoded.
        XCTAssertEqual(incoming([0x0B, 0x15]), .other(group: 0x0B, command: 0x15, data: []))
    }

    func testPluginPageMessages() {
        XCTAssertEqual(RotoOutgoing.pluginCount(4).bytes, head + [0x0B, 0x02, 0x04, 0xF7])
        XCTAssertEqual(RotoOutgoing.firstPlugin(8).bytes, head + [0x0B, 0x03, 0x08, 0xF7])
        XCTAssertEqual(RotoOutgoing.pluginDetailsEnd.bytes, head + [0x0B, 0x06, 0xF7])
        XCTAssertEqual(RotoOutgoing.dawSelectPlugin(index: 2, macroPage: 0, force: true).bytes,
                       head + [0x0B, 0x08, 0x02, 0x00, 0x01, 0xF7])
        let hash = RotoHash(bytes: [1, 2, 3, 4, 5, 6, 7, 8])
        let details = RotoPluginDetails(index: 3, hash: hash, enabled: false, name: "Ch EQ", type: .macro, macroPages: 2)
        XCTAssertEqual(RotoOutgoing.pluginDetails(details).bytes,
                       head + [0x0B, 0x05, 3, 1, 2, 3, 4, 5, 6, 7, 8, 0] + RotoSysEx.encodeName("Ch EQ") + [1, 2, 0xF7])
    }

    func testLearnParameter() {
        let hash = RotoHash(bytes: [9, 8, 7, 6, 5, 4])
        let plain = RotoParameterDetails(index: 200, hash: hash, name: "Main Vol", position: 13388)
        XCTAssertEqual(RotoOutgoing.learnParameter(plain).bytes,
                       head + [0x0B, 0x0A, 0x01, 0x48, 9, 8, 7, 6, 5, 4, 0, 0, 0, 0x68, 0x4C]
                       + RotoSysEx.encodeName("Main Vol") + [0xF7])

        let detent = RotoParameterDetails(index: 0, hash: hash, name: "Pan", position: 8192, centerIndent: true)
        XCTAssertEqual(RotoOutgoing.learnParameter(detent).bytes[15...16], [0, 1], "macro 0, center detent 1")

        let named = RotoParameterDetails(index: 1, hash: hash, name: "Dim", position: 0, steps: 2, stepNames: ["Off", "On"])
        let bytes = RotoOutgoing.learnParameter(named).bytes
        XCTAssertEqual(bytes[17], 2, "steps")
        XCTAssertEqual(bytes.count, 5 + 2 + 2 + 6 + 3 + 2 + 13 + 2 * 13 + 1)
        XCTAssertEqual(RotoSysEx.decodeName(bytes[33..<46]), "Off")
        XCTAssertEqual(RotoSysEx.decodeName(bytes[46..<59]), "On")

        // Missing step names are sent empty; more than 16 steps carry no names.
        let short = RotoParameterDetails(index: 1, hash: hash, name: "Out", position: 0, steps: 4, stepNames: ["A"])
        XCTAssertEqual(RotoOutgoing.learnParameter(short).bytes.count, 5 + 2 + 2 + 6 + 3 + 2 + 13 + 4 * 13 + 1)
        let many = RotoParameterDetails(index: 1, hash: hash, name: "Ratio", position: 0, steps: 20, stepNames: ["x"])
        XCTAssertEqual(RotoOutgoing.learnParameter(many).bytes.count, 5 + 2 + 2 + 6 + 3 + 2 + 13 + 1)
        // Steps outside 2–24 are corrected.
        XCTAssertEqual(RotoParameterDetails(index: 0, hash: hash, name: "", position: 0, steps: 1).steps, 0)
        XCTAssertEqual(RotoParameterDetails(index: 0, hash: hash, name: "", position: 0, steps: 40).steps, 24)
    }

    func testControlMessages() {
        XCTAssertEqual(RotoOutgoing.unmapControl(.switch, control: 3).bytes, head + [0x0B, 0x0E, 0x01, 0x03, 0xF7])
        XCTAssertEqual(RotoOutgoing.controlDetails(.knob, control: 40, name: "Gain 1", colorScheme: 21).bytes,
                       head + [0x0B, 0x13, 0x00, 40] + RotoSysEx.encodeName("Gain 1") + [21, 0xF7])
        XCTAssertEqual(RotoOutgoing.controlDetails(.knob, control: 99, name: "", colorScheme: 99).bytes[8], 63)
        XCTAssertEqual(RotoOutgoing.resetControlDetails(.switch, control: 0).bytes, head + [0x0B, 0x14, 0x01, 0x00, 0xF7])
        let hash = RotoHash(bytes: [1, 1, 1, 1, 1, 1])
        XCTAssertEqual(RotoOutgoing.mappedControlName(parameterIndex: 5, hash: hash, name: "Dim").bytes,
                       head + [0x0B, 0x0F, 0x00, 0x05, 1, 1, 1, 1, 1, 1] + RotoSysEx.encodeName("Dim") + [0xF7])
    }
}
