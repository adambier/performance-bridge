import XCTest
import OSCCodec
import TotalMixOSC
import SurfaceCore
import UDPTransport
@testable import BridgeEngine

final class BridgeEngineTests: XCTestCase {
    func testMonitoringChoicesInOutputOrderWithNamesAndRoles() {
        var mirror = MixerMirror()
        let events: [TotalMixEvent] = [
            .channel(bus: .output, channel: 0, parameter: "name", value: .text("Monitors")),
            .channel(bus: .output, channel: 6, parameter: "name", value: .text("Phones 2")),
            .other(path: "controlroom/mainout", value: .number(0)),
            .other(path: "controlroom/phones1", value: .number(2)),
            .other(path: "controlroom/phones2", value: .number(6)),
            .other(path: "controlroom/mainoutb", value: .number(-1)),
        ]
        for event in events { _ = mirror.apply(event) }
        let choices = BridgeEngine.monitoringChoices(mirror)
        XCTAssertEqual(choices.map(\.output), [0, 2, 6])
        XCTAssertEqual(choices.map(\.name), ["Monitors", "Output 3", "Phones 2"])
        XCTAssertEqual(choices.first?.roles, [.mainOut])
        XCTAssertEqual(choices.last?.roles, [.phones2])
    }

    func testANewEngineIsNotRunning() {
        let engine = BridgeEngine()
        XCTAssertFalse(engine.status.running)
        XCTAssertFalse(engine.status.rotoConnected)
        XCTAssertEqual(engine.settings.endpoint, .standard)
    }

    func testOtherOutputsLeaveOutMonitoringAndHiddenOnes() {
        var mirror = MixerMirror()
        for (number, name) in [(0, "Monitors"), (2, "ADI-2"), (4, "ADAT 1/2"), (6, "ADAT 3/4")] {
            _ = mirror.apply(.channel(bus: .output, channel: number, parameter: "stereo", value: .number(1)))
            _ = mirror.apply(.channel(bus: .output, channel: number, parameter: "name", value: .text(name)))
        }
        _ = mirror.apply(.other(path: "controlroom/mainout", value: .number(0)))
        _ = mirror.apply(.channel(bus: .output, channel: 6, parameter: "color", value: .number(0)))
        let others = BridgeEngine.otherChoices(mirror, layout: PerformanceLayout())
        XCTAssertEqual(others.map(\.name), ["ADI-2", "ADAT 1/2"])
        XCTAssertEqual(others.map(\.name), ["ADI-2", "ADAT 1/2"])
        XCTAssertTrue(others.allSatisfy { $0.roles.isEmpty })
    }

    func testSettingsCarryThePlaybackPageOption() {
        let engine = BridgeEngine(settings: BridgeSettings(playbacksOnNewPage: true))
        XCTAssertTrue(engine.settings.playbacksOnNewPage)
    }

    func testSettingsRetryEveryThreeSecondsByDefault() {
        XCTAssertEqual(BridgeSettings().retryInterval, 3)
    }

    /// TotalMix's port is taken, then freed: the engine runs anyway, says why, and opens the port
    /// on a later try. The Roto-Control is missing throughout (no MIDI here, or no device).
    func testTheEngineKeepsTryingTotalMixsPortAndRunsWithoutTheRotoControl() throws {
        #if os(Windows)
        throw XCTSkip("No UDP sockets on Windows yet")
        #else
        var blocker: UDPSocket? = try UDPSocket(listeningOn: 0, localOnly: true)
        let port = try XCTUnwrap(blocker?.localPort)
        let endpoint = TotalMixEndpoint(host: "127.0.0.1", incomingPort: 9, outgoingPort: port)
        let engine = BridgeEngine(settings: BridgeSettings(endpoint: endpoint, rotoPortName: "No such port here",
                                                           retryInterval: 0.2))
        engine.start()
        defer { engine.stop() }
        XCTAssertTrue(engine.status.running)
        XCTAssertFalse(engine.status.listening)
        XCTAssertFalse(engine.status.rotoFound)
        let error = try XCTUnwrap(engine.status.error)
        XCTAssertTrue(error.contains("Can't listen on port \(port)"), error)
        XCTAssertTrue(error.contains("Roto-Control not found"), error)

        blocker = nil
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, engine.status.error?.contains("Can't listen") == true {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let after = try XCTUnwrap(engine.status.error)
        XCTAssertFalse(after.contains("Can't listen"), after)
        XCTAssertTrue(after.contains("Roto-Control not found"), after)
        XCTAssertTrue(engine.status.listening)
        #endif
    }

    // MARK: The setup checklist

    private func states(_ status: BridgeStatus) -> [String: SetupStep.State] {
        Dictionary(uniqueKeysWithValues: SetupChecklist.steps(status: status, settings: BridgeSettings())
            .map { ($0.id, $0.state) })
    }

    func testSetupChecklistBeforeAnything() {
        var status = BridgeStatus()
        status.listening = true
        let steps = states(status)
        XCTAssertEqual(steps["port"], .done)
        XCTAssertEqual(steps["totalmix"], .waiting)
        XCTAssertEqual(steps["channels"], .waiting)
        XCTAssertEqual(steps["meters"], .optional)
        XCTAssertEqual(steps["roto"], .waiting)
        XCTAssertEqual(steps["hide"], .instruction)
        XCTAssertEqual(steps["order"], .instruction)
        XCTAssertFalse(SetupChecklist.isComplete(status))
    }

    func testSetupChecklistPortInUseIsAProblem() {
        let steps = states(BridgeStatus())
        XCTAssertEqual(steps["port"], .problem)
        XCTAssertEqual(steps["totalmix"], .problem)
    }

    func testSetupChecklistWhenEverythingWorks() {
        var status = BridgeStatus()
        status.listening = true
        status.totalMixAnswering = true
        status.channelCount = 46
        status.levelsSeen = true
        status.rotoFound = true
        status.rotoConnected = true
        let steps = states(status)
        for id in ["port", "totalmix", "channels", "meters", "roto"] { XCTAssertEqual(steps[id], .done, id) }
        XCTAssertTrue(SetupChecklist.isComplete(status))
    }

    func testSetupChecklistNamesTheEnginesPortsAndTotalMixsLabels() throws {
        let settings = BridgeSettings(endpoint: TotalMixEndpoint(host: "127.0.0.1", incomingPort: 7004, outgoingPort: 9004))
        var status = BridgeStatus()
        status.listening = true
        let steps = SetupChecklist.steps(status: status, settings: settings)
        let totalMix = try XCTUnwrap(steps.first { $0.id == "totalmix" })
        XCTAssertTrue(totalMix.detail.contains("“Port (incoming)”: 7004"), totalMix.detail)
        XCTAssertTrue(totalMix.detail.contains("“Port (outgoing)”: 9004"), totalMix.detail)
        XCTAssertTrue(totalMix.detail.contains("Options → Mixer Settings… (F3) → OSC"), totalMix.detail)
        XCTAssertTrue(totalMix.detail.contains("Global OSC"), totalMix.detail)
        status.listening = false
        let port = try XCTUnwrap(SetupChecklist.steps(status: status, settings: settings).first { $0.id == "port" })
        XCTAssertEqual(port.title, "Port 9004 is in use")
    }

    func testSetupChecklistStatusOnlyAnswerSuggestsAskingAgain() throws {
        var status = BridgeStatus()
        status.listening = true
        status.totalMixAnswering = true
        let steps = SetupChecklist.steps(status: status, settings: BridgeSettings())
        let channels = try XCTUnwrap(steps.first { $0.id == "channels" })
        XCTAssertEqual(channels.state, .waiting)
        XCTAssertTrue(channels.detail.contains("Ask TotalMix FX for its state"), channels.detail)
    }

    func testTheEngineCountsChannelsAndSeesLevels() throws {
        #if os(Windows)
        throw XCTSkip("No UDP sockets on Windows yet")
        #else
        var probe: UDPSocket? = try UDPSocket(listeningOn: 0, localOnly: true)
        let port = try XCTUnwrap(probe?.localPort)
        probe = nil   // closes it, leaving the port free for the engine
        let endpoint = TotalMixEndpoint(host: "127.0.0.1", incomingPort: 9, outgoingPort: port)
        let engine = BridgeEngine(settings: BridgeSettings(endpoint: endpoint, rotoPortName: "No such port here",
                                                           retryInterval: 0.2))
        engine.start()
        defer { engine.stop() }
        XCTAssertEqual(engine.status.channelCount, 0)
        XCTAssertFalse(engine.status.levelsSeen)

        let sender = try UDPSocket(listeningOn: 0, localOnly: true)
        try sender.send(OSCMessage("/input/0/name", [.string("ADI-2")]).encoded(), to: "127.0.0.1", port: port)
        try sender.send(OSCMessage("/level/in/0", [.float(-20)]).encoded(), to: "127.0.0.1", port: port)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !(engine.status.channelCount == 1 && engine.status.levelsSeen) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(engine.status.channelCount, 1)
        XCTAssertTrue(engine.status.levelsSeen)
        XCTAssertTrue(engine.status.totalMixAnswering)
        #endif
    }

    // MARK: When the setup window opens by itself

    private func status(listening: Bool = true, answering: Bool = false, found: Bool = false,
                        connected: Bool = false) -> BridgeStatus {
        var status = BridgeStatus()
        status.running = true
        status.listening = listening
        status.totalMixAnswering = answering
        status.rotoFound = found
        status.rotoConnected = connected
        return status
    }

    func testSetupWatchOpensAtOnceForAPortInUseAtLaunch() {
        var watch = SetupWatch(totalMixWorked: true, rotoWorked: true)
        XCTAssertEqual(watch.update(status: status(listening: false), totalMixRunning: false, now: 0), .portInUse)
        XCTAssertNil(watch.update(status: status(listening: false), totalMixRunning: false, now: 1), "only once")
        XCTAssertTrue(watch.needsAttention(status: status(listening: false), now: 1))
    }

    func testSetupWatchIgnoresTheStatusBeforeTheEngineRuns() {
        var watch = SetupWatch(totalMixWorked: false, rotoWorked: false)
        XCTAssertNil(watch.update(status: BridgeStatus(), totalMixRunning: true, now: 0))
        XCTAssertFalse(watch.needsAttention(status: BridgeStatus(), now: 0))
    }

    func testSetupWatchWaitsQuietlyWhileTotalMixIsNotRunning() {
        var watch = SetupWatch(totalMixWorked: false, rotoWorked: false)
        for second in 0...120 {
            XCTAssertNil(watch.update(status: status(), totalMixRunning: false, now: Double(second)))
        }
        XCTAssertFalse(watch.needsAttention(status: status(), now: 120), "TotalMix closed is idle, not a fault")
    }

    func testSetupWatchOpensWhenTotalMixRunsButHasNeverAnswered() {
        var watch = SetupWatch(totalMixWorked: false, rotoWorked: false)
        XCTAssertNil(watch.update(status: status(), totalMixRunning: false, now: 0))
        XCTAssertNil(watch.update(status: status(), totalMixRunning: true, now: 10))   // TotalMix started
        XCTAssertNil(watch.update(status: status(), totalMixRunning: true, now: 39))
        XCTAssertEqual(watch.update(status: status(), totalMixRunning: true, now: 40), .totalMixNotAnswering)
        XCTAssertTrue(watch.needsAttention(status: status(), now: 40))
    }

    func testSetupWatchStaysClosedOnceTotalMixHasWorkedWithTheseSettings() {
        var watch = SetupWatch(totalMixWorked: true, rotoWorked: false)
        for second in 0...120 {
            XCTAssertNil(watch.update(status: status(), totalMixRunning: true, now: Double(second)))
        }
        XCTAssertTrue(watch.needsAttention(status: status(), now: 120), "the mark still shows")

        var fresh = SetupWatch(totalMixWorked: false, rotoWorked: false)
        XCTAssertNil(fresh.update(status: status(answering: true), totalMixRunning: true, now: 0))
        XCTAssertTrue(fresh.totalMixWorked)
        for second in 1...120 {
            XCTAssertNil(fresh.update(status: status(), totalMixRunning: true, now: Double(second)))
        }
    }

    func testSetupWatchMarksASilentRunningTotalMixButNotAClosedOne() {
        var watch = SetupWatch(totalMixWorked: true, rotoWorked: true)
        _ = watch.update(status: status(answering: true), totalMixRunning: true, now: 0)
        XCTAssertFalse(watch.needsAttention(status: status(answering: true), now: 0))
        // Closed: idle, no mark, however long.
        _ = watch.update(status: status(), totalMixRunning: false, now: 10)
        _ = watch.update(status: status(), totalMixRunning: false, now: 100)
        XCTAssertFalse(watch.needsAttention(status: status(), now: 100))
        // Running but silent: a mark after attentionDelay, not before.
        _ = watch.update(status: status(), totalMixRunning: true, now: 200)
        XCTAssertFalse(watch.needsAttention(status: status(), now: 205))
        _ = watch.update(status: status(), totalMixRunning: true, now: 210)
        XCTAssertTrue(watch.needsAttention(status: status(), now: 210))
    }

    func testSetupWatchOpensForAStuckRotoHandshakeOnlyIfItNeverConnected() {
        var watch = SetupWatch(totalMixWorked: true, rotoWorked: false)
        XCTAssertNil(watch.update(status: status(answering: true, found: true), totalMixRunning: true, now: 0))
        XCTAssertNil(watch.update(status: status(answering: true, found: true), totalMixRunning: true, now: 14))
        XCTAssertEqual(watch.update(status: status(answering: true, found: true), totalMixRunning: true, now: 15),
                       .rotoHandshake)

        var worked = SetupWatch(totalMixWorked: true, rotoWorked: true)
        for second in 0...60 {
            XCTAssertNil(worked.update(status: status(answering: true, found: true), totalMixRunning: true,
                                       now: Double(second)))
        }
    }

    func testSetupWatchNeverOpensForAnUnpluggedRotoControl() {
        var watch = SetupWatch(totalMixWorked: true, rotoWorked: false)
        for second in 0...120 {
            XCTAssertNil(watch.update(status: status(answering: true), totalMixRunning: true, now: Double(second)))
        }
        XCTAssertFalse(watch.needsAttention(status: status(answering: true), now: 120))
    }

    func testSetupWatchUnpluggingTheRotoControlIsIdleButAStuckOneIsMarked() {
        var watch = SetupWatch(totalMixWorked: true, rotoWorked: true)
        _ = watch.update(status: status(answering: true, found: true, connected: true), totalMixRunning: true, now: 0)
        _ = watch.update(status: status(answering: true), totalMixRunning: true, now: 5)
        _ = watch.update(status: status(answering: true), totalMixRunning: true, now: 500)
        XCTAssertFalse(watch.needsAttention(status: status(answering: true), now: 500), "unplugged is idle")
        _ = watch.update(status: status(answering: true, found: true), totalMixRunning: true, now: 600)
        XCTAssertFalse(watch.needsAttention(status: status(answering: true, found: true), now: 605))
        _ = watch.update(status: status(answering: true, found: true), totalMixRunning: true, now: 610)
        XCTAssertTrue(watch.needsAttention(status: status(answering: true, found: true), now: 610))
    }

    func testSetupWatchOpensAtOnceForATotalMixTooOld() {
        var watch = SetupWatch(totalMixWorked: true, rotoWorked: true)
        XCTAssertNil(watch.update(status: status(), totalMixRunning: false, now: 0, totalMixTooOld: true))
        XCTAssertEqual(watch.update(status: status(), totalMixRunning: true, now: 1, totalMixTooOld: true), .totalMixTooOld)
    }

    func testSetupChecklistVersionStep() {
        func version(running: Bool, _ text: String?, answering: Bool = false) -> SetupStep {
            var status = BridgeStatus()
            status.listening = true
            status.totalMixAnswering = answering
            return SetupChecklist.steps(status: status, settings: BridgeSettings(), totalMixRunning: running,
                                        totalMixVersion: text).first { $0.id == "version" }!
        }
        XCTAssertEqual(version(running: false, nil).state, .waiting)
        XCTAssertEqual(version(running: true, nil).state, .instruction)
        XCTAssertEqual(version(running: true, "2.10 (1)").state, .done)
        XCTAssertEqual(version(running: true, "2.10 (1)").title, "TotalMix FX 2.10 (1) has Global OSC")
        XCTAssertEqual(version(running: true, "2.1 RC1").state, .done)
        XCTAssertEqual(version(running: true, "1.96").state, .problem)
        XCTAssertEqual(version(running: false, "2.10", answering: true).state, .done, "an answer means it runs")
    }
}
