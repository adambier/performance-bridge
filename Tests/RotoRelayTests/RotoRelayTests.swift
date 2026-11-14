import XCTest
@testable import RotoRelay
import RotoControl

/// One test for each routing rule of the relay (docs/PLUGIN-MODE-PLAN.md, sections 2–4), with the
/// messages written out as bytes.
final class RotoRelayTests: XCTestCase {
    private static let head: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02]

    /// A Roto-Control SysEx message: the header, the given bytes, and `F7`.
    private func sx(_ body: UInt8...) -> [UInt8] { Self.head + body + [0xF7] }

    private let setPluginMode: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02, 0x0B, 0x01, 0x00, 0xF7]
    private let setMixAllTracks: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02, 0x0C, 0x01, 0x00, 0x00, 0x00, 0x00, 0xF7]
    private let setMixTrack: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02, 0x0C, 0x02, 0x00, 0xF7]
    private let requestTransport: [UInt8] = [0xF0, 0x00, 0x22, 0x03, 0x02, 0x0A, 0x0A, 0xF7]

    private func relayInPluginMode() -> RotoRelay {
        var relay = RotoRelay()
        _ = relay.fromDevice(setPluginMode)
        return relay
    }

    // MARK: The mode

    func testStartsInMixModeUnlessTold() {
        XCTAssertEqual(RotoRelay().knobMode, .mix)
        XCTAssertFalse(RotoRelay().transportSwitchesActive)
        XCTAssertEqual(RotoRelay(initialMode: .plugin).knobMode, .plugin)
    }

    func testModeFollowsTheDevice() {
        var relay = RotoRelay()
        _ = relay.fromDevice(setPluginMode)
        XCTAssertEqual(relay.knobMode, .plugin)
        _ = relay.fromDevice(setMixAllTracks)
        XCTAssertEqual(relay.knobMode, .mix)
        _ = relay.fromDevice(setPluginMode)
        XCTAssertEqual(relay.knobMode, .plugin)
        _ = relay.fromDevice(setMixTrack)
        XCTAssertEqual(relay.knobMode, .mix)
        // SET ALL TRACKS MODE (0C 05) does not change the mode.
        _ = relay.fromDevice(setPluginMode)
        _ = relay.fromDevice(sx(0x0C, 0x05, 0x01))
        XCTAssertEqual(relay.knobMode, .plugin)
    }

    func testTransportSwitchesAreALayerOverTheKnobMode() {
        var relay = RotoRelay()
        _ = relay.fromDevice(requestTransport)
        XCTAssertTrue(relay.transportSwitchesActive)
        XCTAssertEqual(relay.knobMode, .mix, "the knobs stay where they were")
        _ = relay.fromDevice(setMixAllTracks)
        XCTAssertFalse(relay.transportSwitchesActive, "ended by 0C 01")

        _ = relay.fromDevice(setPluginMode)
        _ = relay.fromDevice(requestTransport)
        XCTAssertTrue(relay.transportSwitchesActive)
        XCTAssertEqual(relay.knobMode, .plugin)
        _ = relay.fromDevice(setPluginMode)
        XCTAssertFalse(relay.transportSwitchesActive, "ended by 0B 01")
        XCTAssertEqual(relay.knobMode, .plugin)

        _ = relay.fromDevice(requestTransport)
        _ = relay.fromDevice(setMixTrack)
        XCTAssertFalse(relay.transportSwitchesActive, "ended by 0C 02")
    }

    // MARK: From the host

    func testHostHandshakeMessagesAreAlwaysSwallowed() {
        for var relay in [RotoRelay(), relayInPluginMode()] {
            for message in [sx(0x0A, 0x01), sx(0x0A, 0x03, 0x02), sx(0x0A, 0x0D)] {
                let output = relay.fromHost(message)
                XCTAssertEqual(output.toDevice, [])
                // DAW STARTED in PLUGIN mode is answered by the relay (the tests below).
                if !(message == sx(0x0A, 0x01) && relay.knobMode == .plugin) { XCTAssertEqual(output.toHost, []) }
                XCTAssertEqual(output.dropped, [message])
            }
        }
    }

    func testDAWStartedInPluginModeSendsTheHostSetPluginMode() {
        var relay = relayInPluginMode()
        let output = relay.fromHost(sx(0x0A, 0x01))
        XCTAssertEqual(output.toHost, [[0xF0, 0x00, 0x22, 0x03, 0x02, 0x0B, 0x01, 0x00, 0xF7]])
        XCTAssertEqual(output.toDevice, [])
        XCTAssertEqual(output.dropped, [sx(0x0A, 0x01)])
        XCTAssertEqual(output.decisions.map(\.source), [.host, .relay])
        XCTAssertEqual(relay.knobMode, .plugin)
    }

    func testDAWStartedWithTransportSwitchesActiveSendsTheHostRequestTransportStatus() {
        // In MIX mode: the request alone.
        var relay = RotoRelay()
        _ = relay.fromDevice(requestTransport)
        let output = relay.fromHost(sx(0x0A, 0x01))
        XCTAssertEqual(output.toHost, [[0xF0, 0x00, 0x22, 0x03, 0x02, 0x0A, 0x0A, 0xF7]])
        XCTAssertEqual(output.toDevice, [])
        XCTAssertTrue(relay.transportSwitchesActive)
        // In PLUGIN mode: SET PLUGIN MODE first.
        var inPlugin = relayInPluginMode()
        _ = inPlugin.fromDevice(requestTransport)
        XCTAssertEqual(inPlugin.fromHost(sx(0x0A, 0x01)).toHost, [setPluginMode, requestTransport])
    }

    func testDAWStartedInMixModeWithoutTransportSendsTheHostNothing() {
        var relay = RotoRelay()
        let output = relay.fromHost(sx(0x0A, 0x01))
        XCTAssertEqual(output.toHost, [])
        XCTAssertEqual(output.toDevice, [])
        XCTAssertEqual(output.decisions.count, 1)
        // The transport switches' layer has ended.
        _ = relay.fromDevice(requestTransport)
        _ = relay.fromDevice(setMixAllTracks)
        XCTAssertEqual(relay.fromHost(sx(0x0A, 0x01)).toHost, [])
    }

    func testFirmwareVersionRequestIsAnsweredWhenKnown() {
        let version = sx(0x0A, 0x0E, 0x01, 0x02, 0x03, 0x61, 0x62, 0x63, 0x00)
        var relay = RotoRelay()
        // The device's reply is kept and never passed to the host.
        let fromDevice = relay.fromDevice(version)
        XCTAssertEqual(fromDevice.forLocal, [version])
        XCTAssertEqual(fromDevice.toHost, [])
        XCTAssertEqual(relay.firmwareVersionReply, version)
        let output = relay.fromHost(sx(0x0A, 0x0D))
        XCTAssertEqual(output.toHost, [version])
        XCTAssertEqual(output.toDevice, [])

        // Fed in from elsewhere.
        var other = RotoRelay(initialMode: .plugin)
        XCTAssertEqual(other.fromHost(sx(0x0A, 0x0D)).toHost, [])
        other.firmwareVersionReply = version
        XCTAssertEqual(other.fromHost(sx(0x0A, 0x0D)).toHost, [version])
    }

    func testHostTrafficPassesInPluginMode() {
        var relay = relayInPluginMode()
        let messages: [[UInt8]] = [
            sx(0x0B, 0x02, 0x03),                         // NUM PLUGINS
            sx(0x0A, 0x04, 0x00, 0x10),                   // NUM TRACKS
            sx(0x0A, 0x0B, 1, 0, 0, 0, 0, 0, 0, 0),       // TRANSPORT STATUS
            sx(0x0A, 0x18, 0x00, 0x00, 0x41, 0x00),       // SHOW CONTROL VALUE
            [0xBF, 12, 0x40], [0xBF, 44, 0x00],           // knob 1's position
            [0xBF, 20, 0x7F],                             // switch 1's light
            [0xB0, 7, 100],                               // another channel
            [0x90, 60, 100],                              // not a control change
            [0xF0, 0x00, 0x20, 0x29, 0x01, 0xF7],         // another maker's SysEx
        ]
        for message in messages {
            XCTAssertEqual(relay.fromHost(message).toDevice, [message])
        }
    }

    func testHostTrafficIsDroppedInMixMode() {
        var relay = RotoRelay()
        let messages: [[UInt8]] = [
            sx(0x0B, 0x02, 0x03),
            sx(0x0B, 0x08, 0x00, 0x00, 0x00),
            sx(0x0A, 0x04, 0x00, 0x10),
            sx(0x0A, 0x0B, 1, 0, 0, 0, 0, 0, 0, 0),
            sx(0x0C, 0x03, 0x04),
            [0xBF, 12, 0x40], [0xBF, 44, 0x00],
            [0xBF, 28, 0x7F],
            [0x90, 60, 100],
            [0xF0, 0x00, 0x20, 0x29, 0x01, 0xF7],
        ]
        for message in messages {
            let output = relay.fromHost(message)
            XCTAssertEqual(output.toDevice, [], "\(message)")
            XCTAssertEqual(output.dropped, [message])
        }
    }

    func testHostTransportPassesInMixModeWhileTransportSwitchesAreActive() {
        var relay = RotoRelay()
        _ = relay.fromDevice(requestTransport)
        let status = sx(0x0A, 0x0B, 1, 0, 0, 0, 0, 0, 0, 0)
        XCTAssertEqual(relay.fromHost(status).toDevice, [status])
        XCTAssertEqual(relay.fromHost([0xBF, 28, 0x7F]).toDevice, [[0xBF, 28, 0x7F]])
        XCTAssertEqual(relay.fromHost([0xBF, 35, 0x00]).toDevice, [[0xBF, 35, 0x00]])
        // Not transport: CC 36 and 37 (the device's only), another channel, knobs, and other SysEx.
        XCTAssertEqual(relay.fromHost([0xBF, 36, 0x7F]).toDevice, [])
        XCTAssertEqual(relay.fromHost([0xBF, 27, 0x7F]).toDevice, [])
        XCTAssertEqual(relay.fromHost([0xB0, 28, 0x7F]).toDevice, [])
        XCTAssertEqual(relay.fromHost([0xBF, 12, 0x40]).toDevice, [])
        XCTAssertEqual(relay.fromHost(sx(0x0B, 0x02, 0x03)).toDevice, [])
        // The layer ends, and transport is dropped again.
        _ = relay.fromDevice(setMixAllTracks)
        XCTAssertEqual(relay.fromHost(status).toDevice, [])
        XCTAssertEqual(relay.fromHost([0xBF, 28, 0x7F]).toDevice, [])
    }

    // MARK: From the device

    func testMixModeMessagesNeverReachTheHost() {
        for var relay in [RotoRelay(), relayInPluginMode()] {
            for message in [setMixAllTracks, setMixTrack, sx(0x0C, 0x05, 0x01)] {
                let output = relay.fromDevice(message)
                XCTAssertEqual(output.toHost, [])
                XCTAssertEqual(output.forLocal, [message])
                // Back to PLUGIN mode for the next message, where the relay started there.
                if relay.knobMode == .mix, message != sx(0x0C, 0x05, 0x01) { _ = relay.fromDevice(setPluginMode) }
            }
        }
    }

    func testHandshakeAndVersionRepliesStayLocal() {
        for var relay in [RotoRelay(), relayInPluginMode()] {
            for message in [sx(0x0A, 0x0C), sx(0x0A, 0x02), sx(0x0A, 0x0E, 1, 0, 0, 0), sx(0x0A, 0x10, 1, 6)] {
                let output = relay.fromDevice(message)
                XCTAssertEqual(output.toHost, [])
                XCTAssertEqual(output.forLocal, [message])
            }
        }
    }

    func testDeviceSysExPassesToTheHostInPluginMode() {
        var relay = relayInPluginMode()
        let passed: [[UInt8]] = [
            sx(0x0B, 0x04, 0x08),                         // SET FIRST PLUGIN
            sx(0x0B, 0x07, 0x01),                         // ROTO SELECT PLUGIN
            sx(0x0B, 0x10, 0x01),                         // MACRO PLUGIN PAGE INDEX
            sx(0x0B, 0x7E),                               // any 0B message
            sx(0x0A, 0x06, 0x00, 0x08),                   // SET FIRST TRACK
            sx(0x0A, 0x09, 0x00, 0x02),                   // ROTO SELECT TRACK
            requestTransport,
            sx(0x0C, 0x06, 0x00, 0x01),                   // TOGGLE TRACK GROUPING
            sx(0x0C, 0x07, 0x00),                         // REQUEST SEND TRACK NAMES
        ]
        for message in passed {
            let output = relay.fromDevice(message)
            XCTAssertEqual(output.toHost, [message])
            XCTAssertEqual(output.forLocal, [])
        }
        for message in [sx(0x0A, 0x14), sx(0x0C, 0x7E), [0xF0, 0x00, 0x20, 0x29, 0x01, 0xF7]] {
            let output = relay.fromDevice(message)
            XCTAssertEqual(output.toHost, [])
            XCTAssertEqual(output.forLocal, [message])
        }
    }

    func testDeviceControlsPassToTheHostInPluginMode() {
        var relay = relayInPluginMode()
        for controller: UInt8 in [12, 19, 44, 51, 20, 27, 52, 59, 28, 37] {
            let message: [UInt8] = [0xBF, controller, 0x40]
            XCTAssertEqual(relay.fromDevice(message).toHost, [message], "CC \(controller)")
        }
        for controller: UInt8 in [11, 38, 43, 60, 64, 65] {
            let message: [UInt8] = [0xBF, controller, 0x40]
            let output = relay.fromDevice(message)
            XCTAssertEqual(output.toHost, [], "CC \(controller)")
            XCTAssertEqual(output.forLocal, [message])
        }
        // Another channel, and a message that is not a control change.
        XCTAssertEqual(relay.fromDevice([0xB0, 12, 0x40]).forLocal, [[0xB0, 12, 0x40]])
        XCTAssertEqual(relay.fromDevice([0x90, 60, 100]).forLocal, [[0x90, 60, 100]])
    }

    func testDeviceTrafficStaysLocalInMixMode() {
        var relay = RotoRelay()
        let messages: [[UInt8]] = [
            sx(0x0A, 0x06, 0x00, 0x08), sx(0x0A, 0x09, 0x00, 0x02), sx(0x0C, 0x06, 0x00, 0x01), sx(0x0C, 0x07, 0x00),
            sx(0x0B, 0x04, 0x08),
            [0xBF, 12, 0x40], [0xBF, 44, 0x00], [0xBF, 20, 0x7F], [0xBF, 52, 0x7F], [0xBF, 28, 0x7F], [0xBF, 64, 0x00],
        ]
        for message in messages {
            let output = relay.fromDevice(message)
            XCTAssertEqual(output.toHost, [], "\(message)")
            XCTAssertEqual(output.forLocal, [message])
        }
    }

    func testDeviceTransportReachesTheHostInMixMode() {
        var relay = RotoRelay()
        let request = relay.fromDevice(requestTransport)
        XCTAssertEqual(request.toHost, [requestTransport])
        XCTAssertEqual(request.forLocal, [])
        for controller: UInt8 in [28, 35, 36, 37] {
            let message: [UInt8] = [0xBF, controller, 0x7F]
            XCTAssertEqual(relay.fromDevice(message).toHost, [message], "CC \(controller)")
        }
        // Knobs, switches, and touches stay local, as does transport on another channel.
        for message: [UInt8] in [[0xBF, 12, 0x40], [0xBF, 27, 0x7F], [0xBF, 38, 0x7F], [0xBF, 52, 0x7F], [0xB0, 28, 0x7F]] {
            let output = relay.fromDevice(message)
            XCTAssertEqual(output.toHost, [])
            XCTAssertEqual(output.forLocal, [message])
        }
        _ = relay.fromDevice(setMixTrack)
        XCTAssertEqual(relay.fromDevice([0xBF, 28, 0x7F]).toHost, [], "the layer has ended")
    }

    // MARK: Entering PLUGIN mode

    func testSetPluginModePassesToTheHostAndNothingIsReplayedWhenNothingIsRemembered() {
        var relay = RotoRelay()
        let output = relay.fromDevice(setPluginMode)
        XCTAssertEqual(output.toHost, [setPluginMode])
        XCTAssertEqual(output.toDevice, [])
        XCTAssertEqual(output.forLocal, [])
    }

    func testRememberAndReplay() {
        let numTracks = sx(0x0A, 0x04, 0x00, 0x03)
        let firstTrack = sx(0x0A, 0x05, 0x00, 0x00)
        let track1 = sx(0x0A, 0x07, 0x00, 0x00, 0x41, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x05, 0x00)
        let track2 = sx(0x0A, 0x07, 0x00, 0x01, 0x42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x06, 0x00)
        let track3 = sx(0x0A, 0x07, 0x00, 0x02, 0x43, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x07, 0x00)
        let end = sx(0x0A, 0x08)
        let sendCount = sx(0x0C, 0x03, 0x02)
        let sendNames = sx(0x0C, 0x08, 0x00, 0x53, 0x00)
        let selectTrack = sx(0x0C, 0x04, 0x00, 0x01, 0x42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x06, 0x00)

        var relay = relayInPluginMode()
        // The sends and the selected track in another order than the replay's; NUM TRACKS and
        // FIRST TRACK before the details, as Bitwig's integration sends them, with another
        // message between the details.
        for message in [selectTrack, sendNames, sendCount, numTracks, firstTrack, track1, sx(0x0B, 0x02, 0x01), track2, end] {
            XCTAssertEqual(relay.fromHost(message).toDevice, [message], "passed as well as remembered")
        }
        _ = relay.fromDevice(setMixAllTracks)
        let output = relay.fromDevice(setPluginMode)
        XCTAssertEqual(output.toHost, [setPluginMode])
        XCTAssertEqual(output.toDevice, [numTracks, firstTrack, track1, track2, end, sendCount, sendNames, selectTrack])
        XCTAssertEqual(output.decisions.first?.route, .toHost, "SET PLUGIN MODE goes to the host before the replay")
        XCTAssertEqual(output.decisions.dropFirst().map(\.source), Array(repeating: .relay, count: 8))

        // A new page starts a new list. Messages dropped in MIX mode are remembered too.
        _ = relay.fromDevice(setMixTrack)
        let newCount = sx(0x0A, 0x04, 0x00, 0x01)
        XCTAssertEqual(relay.fromHost(newCount).toDevice, [])
        XCTAssertEqual(relay.fromHost(track3).toDevice, [])
        XCTAssertEqual(relay.fromHost(end).toDevice, [])
        XCTAssertEqual(relay.fromDevice(setPluginMode).toDevice,
                       [newCount, firstTrack, track3, end, sendCount, sendNames, selectTrack])

        // A new TRACK DETAILS after TRACK DETAILS END starts a new list too, with no NUM TRACKS.
        XCTAssertEqual(relay.fromHost(track1).toDevice, [track1])
        XCTAssertEqual(relay.fromHost(end).toDevice, [end])
        XCTAssertEqual(relay.replayOnEnteringPluginMode,
                       [newCount, firstTrack, track1, end, sendCount, sendNames, selectTrack])

        // No replay on SET PLUGIN MODE while already in PLUGIN mode.
        let again = relay.fromDevice(setPluginMode)
        XCTAssertEqual(again.toHost, [setPluginMode])
        XCTAssertEqual(again.toDevice, [])
    }

    func testNumTracksAndFirstTrackClearTheRememberedTrackDetails() {
        let numTracks = sx(0x0A, 0x04, 0x00, 0x02)
        let firstTrack = sx(0x0A, 0x05, 0x00, 0x00)
        let track1 = sx(0x0A, 0x07, 0x00, 0x00, 0x41, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x05, 0x00)
        let track2 = sx(0x0A, 0x07, 0x00, 0x01, 0x42, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x06, 0x00)
        let end = sx(0x0A, 0x08)
        var relay = relayInPluginMode()
        for message in [numTracks, firstTrack, track1, track2, end] { _ = relay.fromHost(message) }
        XCTAssertEqual(relay.replayOnEnteringPluginMode, [numTracks, firstTrack, track1, track2, end])

        // A project with no tracks: NUM TRACKS, FIRST TRACK, and TRACK DETAILS END, no details.
        let noTracks = sx(0x0A, 0x04, 0x00, 0x00)
        _ = relay.fromHost(noTracks)
        XCTAssertEqual(relay.replayOnEnteringPluginMode, [noTracks, firstTrack, end], "cleared by NUM TRACKS alone")
        for message in [firstTrack, end] { _ = relay.fromHost(message) }
        XCTAssertEqual(relay.replayOnEnteringPluginMode, [noTracks, firstTrack, end])

        // FIRST TRACK alone clears an unfinished list as well.
        _ = relay.fromHost(track1)
        XCTAssertEqual(relay.replayOnEnteringPluginMode, [noTracks, firstTrack, track1, end])
        let second = sx(0x0A, 0x05, 0x00, 0x08)
        _ = relay.fromHost(second)
        XCTAssertEqual(relay.replayOnEnteringPluginMode, [noTracks, second, end])
    }

    func testReplayEndsAnUnfinishedListOfTrackDetails() {
        let track1 = sx(0x0A, 0x07, 0x00, 0x00, 0x41, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x05, 0x00)
        var relay = RotoRelay()
        _ = relay.fromHost(track1)
        XCTAssertEqual(relay.replayOnEnteringPluginMode, [track1, sx(0x0A, 0x08)])
        XCTAssertEqual(RotoRelay().replayOnEnteringPluginMode, [])
    }

    // MARK: The byte stream

    func testSysExSplitAcrossCalls() {
        var relay = RotoRelay()
        XCTAssertEqual(relay.fromDevice([0xF0, 0x00, 0x22]).decisions, [])
        XCTAssertEqual(relay.fromDevice([0x03, 0x02, 0x0B]).decisions, [])
        XCTAssertEqual(relay.knobMode, .mix)
        let output = relay.fromDevice([0x01, 0x00, 0xF7])
        XCTAssertEqual(output.toHost, [setPluginMode])
        XCTAssertEqual(relay.knobMode, .plugin)

        let numPlugins = sx(0x0B, 0x02, 0x03)
        XCTAssertEqual(relay.fromHost(Array(numPlugins.prefix(4))).decisions, [])
        XCTAssertEqual(relay.fromHost(Array(numPlugins.dropFirst(4))).toDevice, [numPlugins])
        // The two sides' partial messages do not mix.
        XCTAssertEqual(relay.fromHost(Array(numPlugins.prefix(6))).decisions, [])
        XCTAssertEqual(relay.fromDevice(sx(0x0B, 0x04, 0x00)).toHost, [sx(0x0B, 0x04, 0x00)])
        XCTAssertEqual(relay.fromHost(Array(numPlugins.dropFirst(6))).toDevice, [numPlugins])
    }

    func testMixedStreamWithRunningStatus() {
        var relay = relayInPluginMode()
        // Knob 1's two CCs with running status, a SysEx message, a complete CC, and a CC split
        // across calls.
        let stream: [UInt8] = [0xBF, 12, 0x40, 44, 0x01] + sx(0x0B, 0x07, 0x02) + [0xBF, 52, 0x7F, 0xBF, 20]
        let output = relay.fromDevice(stream)
        XCTAssertEqual(output.toHost, [[0xBF, 12, 0x40], [0xBF, 44, 0x01], sx(0x0B, 0x07, 0x02), [0xBF, 52, 0x7F]])
        XCTAssertEqual(relay.fromDevice([0x7F]).toHost, [[0xBF, 20, 0x7F]])

        let fromHost = relay.fromHost([0xBF, 12, 0x20, 44, 0x00] + sx(0x0B, 0x06) + [0xBF, 21, 0x7F])
        XCTAssertEqual(fromHost.toDevice, [[0xBF, 12, 0x20], [0xBF, 44, 0x00], sx(0x0B, 0x06), [0xBF, 21, 0x7F]])
    }

    func testAChangeOfModeInsideOneCallAppliesToWhatFollows() {
        var relay = RotoRelay()
        let output = relay.fromDevice([0xBF, 12, 0x40] + setPluginMode + [0xBF, 12, 0x41] + setMixAllTracks + [0xBF, 12, 0x42])
        XCTAssertEqual(output.forLocal, [[0xBF, 12, 0x40], setMixAllTracks, [0xBF, 12, 0x42]])
        XCTAssertEqual(output.toHost, [setPluginMode, [0xBF, 12, 0x41]])
    }

    // MARK: The log

    func testDecisionDescriptions() {
        var relay = RotoRelay()
        let dropped = relay.fromHost(sx(0x0A, 0x01)).decisions
        XCTAssertEqual(dropped.count, 1)
        XCTAssertEqual(dropped[0].direction, "dropped host")
        XCTAssertEqual(dropped[0].description, "dropped host  F0 00 22 03 02 0A 01 F7   [DAW STARTED: never passed to the device]")
        XCTAssertEqual(relay.fromDevice(setMixAllTracks).decisions[0].direction, "device → local")
        XCTAssertEqual(relay.fromDevice(setPluginMode).decisions[0].direction, "device → host")
        XCTAssertEqual(relay.fromHost([0xBF, 12, 0x05]).decisions[0].description, "host → device  BF 0C 05   [PLUGIN mode]")
        _ = relay.fromHost(sx(0x0C, 0x03, 0x02))
        _ = relay.fromDevice(setMixTrack)
        XCTAssertEqual(relay.fromDevice(setPluginMode).decisions.last?.direction, "relay → device")
    }
}
