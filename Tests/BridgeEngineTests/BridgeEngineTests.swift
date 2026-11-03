import XCTest
import OSCCodec
import TotalMixOSC
import SurfaceCore
import UDPTransport
import LaunchControl
import LaunchControlDriver
import MIDITransport
@testable import BridgeEngine

final class BridgeEngineTests: XCTestCase {
    func testALaunchControlCanBeChosenOnTheCommandLine() {
        XCTAssertNil(LaunchControlSetting(arguments: ["app"]))
        XCTAssertNil(LaunchControlSetting(arguments: ["app", "--launch-control", "mk2"]))
        let xl3 = LaunchControlSetting(arguments: ["app", "--launch-control", "xl3"])
        XCTAssertEqual(xl3?.layout, .xl3)
        XCTAssertNil(xl3?.portName, "found by name unless given")
        XCTAssertEqual(xl3?.name, "Launch Control XL 3")
        let sim = LaunchControlSetting(arguments: ["app", "--launch-control", "lc3-sim", "--launch-control-port", "LCXL3 2 DAW"])
        XCTAssertEqual(sim?.layout, .lc3)
        XCTAssertEqual(sim?.device, .xl3)
        XCTAssertEqual(sim?.portName, "LCXL3 2 DAW")
        XCTAssertEqual(sim?.name, "Launch Control 3 on a Launch Control XL 3")
        XCTAssertEqual(LaunchControlSetting(arguments: ["app", "--launch-control", "lc3"])?.device, .lc3)
    }

    func testTheEngineHoldsBothLayoutsSendRowsWithNoDevice() throws {
        #if os(Windows)
        throw XCTSkip("No UDP sockets on Windows yet")
        #else
        var probe: UDPSocket? = try UDPSocket(listeningOn: 0, localOnly: true)
        let port = try XCTUnwrap(probe?.localPort)
        probe = nil
        let endpoint = TotalMixEndpoint(host: "127.0.0.1", incomingPort: 9, outgoingPort: port)
        var settings = BridgeSettings(endpoint: endpoint, rotoPortName: "No such port here", retryInterval: 0.2)
        settings.rotoEnabled = false
        settings.launchControlSends = [.lc3: [nil]]
        let engine = BridgeEngine(settings: settings)
        let saved = SavedRows()
        engine.onLaunchControlSendsChange = { layout, choices in saved.append(layout, choices) }
        engine.start()
        defer { engine.stop() }

        let sender = try UDPSocket(listeningOn: 0, localOnly: true)
        for (channel, name) in [(0, "Main"), (2, "Phones 1"), (4, "Phones 2"), (6, "Line 7/8")] {
            try sender.send(OSCMessage("/output/\(channel)/name", [.string(name)]).encoded(), to: "127.0.0.1", port: port)
        }
        try sender.send(OSCMessage("/controlroom/mainout", [.float(0)]).encoded(), to: "127.0.0.1", port: port)
        let deadline = Date().addingTimeInterval(3)
        // Wait for the names and Main Out's assignment, which can be handled after three of the
        // names (seen once on CI's macOS runner, 2026-11-02).
        while Date() < deadline, engine.status.sendTargets.map(\.output) != [2, 4, 6] { Thread.sleep(forTimeInterval: 0.05) }
        let targets = engine.status.sendTargets.map(\.output)
        XCTAssertGreaterThanOrEqual(targets.count, 3)
        guard targets.count >= 3 else { return }

        // No Launch Control is connected, yet both layouts' rows resolve against TotalMix FX's outputs.
        XCTAssertEqual(engine.status.launchControlSends[.xl3], [targets[0], targets[1]])
        XCTAssertEqual(engine.status.launchControlSends[.lc3], [nil], "pan")

        engine.setLaunchControlSend(layout: .xl3, row: 1, to: targets[2])
        XCTAssertEqual(engine.status.launchControlSends[.xl3], [targets[0], targets[2]])
        engine.setLaunchControlSend(layout: .xl3, row: 0, to: targets[2])   // the other row's: refused
        XCTAssertEqual(engine.status.launchControlSends[.xl3], [targets[0], targets[2]])
        engine.setLaunchControlSend(layout: .lc3, row: 0, to: targets[1])
        XCTAssertEqual(engine.status.launchControlSends[.lc3], [targets[1]])

        // The row the user didn't touch is pinned to what it showed, so it can't move later.
        XCTAssertEqual(saved.all.map(\.0), [.xl3, .lc3])
        XCTAssertEqual(saved.all.first?.1, [targets[0], targets[2]])
        XCTAssertEqual(saved.all.last?.1, [targets[1]])

        // Level by brightness: off unless saved on, and held with no device (Adam, 2026-11-02).
        XCTAssertFalse(engine.status.launchControlLevelBrightness)
        engine.setLaunchControlLevelBrightness(true)
        XCTAssertTrue(engine.status.launchControlLevelBrightness)
        var savedOn = BridgeSettings()
        savedOn.launchControlLevelBrightness = true
        XCTAssertTrue(BridgeEngine(settings: savedOn).status.launchControlLevelBrightness, "a saved setting is taken up")
        #endif
    }

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

    /// TotalMix FX's port is taken, then freed: the engine runs anyway, says why, and opens the port
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
        XCTAssertEqual(steps["order"], .optional)
        XCTAssertFalse(SetupChecklist.isComplete(status))
    }

    func testSetupChecklistAndWatchCoverALaunchControl() {
        var status = BridgeStatus()
        status.running = true
        status.listening = true
        status.totalMixAnswering = true
        status.channelCount = 46
        status.rotoConnected = true
        XCTAssertNil(states(status)["launchcontrol"], "no step without a Launch Control")
        var launchOnly = status
        launchOnly.rotoEnabled = false
        launchOnly.rotoConnected = false
        XCTAssertNil(states(launchOnly)["roto"], "no Roto-Control step while a Launch Control is the controller")
        XCTAssertTrue(SetupChecklist.isComplete(status))
        status.launchControlName = "Launch Control XL 3"
        XCTAssertEqual(states(status)["launchcontrol"], .waiting)
        XCTAssertFalse(SetupChecklist.isComplete(status))
        status.launchControlFound = true
        var watch = SetupWatch(totalMixWorked: true, rotoWorked: true)
        _ = watch.update(status: status, totalMixRunning: true, now: 0)
        _ = watch.update(status: status, totalMixRunning: true, now: 11)
        XCTAssertTrue(watch.needsAttention(status: status, now: 11), "plugged in but not in DAW mode: the mark")
        XCTAssertEqual(watch.update(status: status, totalMixRunning: true, now: 15), .launchControlNotConnecting,
                       "never worked with these settings: the Setup Guide opens")
        status.launchControlConnected = true
        _ = watch.update(status: status, totalMixRunning: true, now: 12)
        XCTAssertFalse(watch.needsAttention(status: status, now: 12))
        XCTAssertEqual(states(status)["launchcontrol"], .done)
        XCTAssertTrue(SetupChecklist.isComplete(status))
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
        XCTAssertNil(steps["mutemaster"], "no Mute Master step while it is on or unknown")
        status.muteMasterOff = true
        XCTAssertEqual(states(status)["mutemaster"], .problem)
        XCTAssertEqual(steps["livemode"], .instruction, "Live mode can't be read, so it's a note")
        XCTAssertEqual(steps["cue"], .instruction, "nor can Cue/PFL to")
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
        XCTAssertTrue(channels.detail.contains("Refresh Channels from TotalMix FX"), channels.detail)
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

    func testTheSavedLayoutIsUsedAndLabelChangesAreReported() throws {
        #if os(Windows)
        throw XCTSkip("No UDP sockets on Windows yet")
        #else
        var probe: UDPSocket? = try UDPSocket(listeningOn: 0, localOnly: true)
        let port = try XCTUnwrap(probe?.localPort)
        probe = nil
        let endpoint = TotalMixEndpoint(host: "127.0.0.1", incomingPort: 9, outgoingPort: port)
        var settings = BridgeSettings(endpoint: endpoint, rotoPortName: "No such port here", retryInterval: 0.2)
        settings.layout = PerformanceLayout().withLabel("Vox", for: ChannelRef(.input, 0))
        let engine = BridgeEngine(settings: settings)
        let saved = SavedLayouts()
        engine.onLayoutChange = { saved.append($0) }
        engine.start()
        defer { engine.stop() }
        XCTAssertEqual(engine.layout.label(for: ChannelRef(.input, 0)), "Vox", "the saved layout is used at start")

        let sender = try UDPSocket(listeningOn: 0, localOnly: true)
        try sender.send(OSCMessage("/input/0/name", [.string("ADI-2")]).encoded(), to: "127.0.0.1", port: port)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, engine.layoutItems(.sources).isEmpty { Thread.sleep(forTimeInterval: 0.05) }
        let item = try XCTUnwrap(engine.layoutItems(.sources).first)
        XCTAssertEqual(item.name, "Vox")
        XCTAssertEqual(item.defaultName, "ADI-2")
        XCTAssertEqual(item.label, "Vox")

        engine.setLabel("", for: ChannelRef(.input, 0))
        XCTAssertEqual(engine.layoutItems(.sources).first?.name, "ADI-2", "clearing the label shows TotalMix FX's name")
        XCTAssertEqual(saved.all.last?.labels, [:], "the change is reported, for the app to save")
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
        XCTAssertFalse(watch.needsAttention(status: status(), now: 120), "TotalMix FX closed is idle, not a fault")
    }

    func testSetupWatchOpensWhenTotalMixRunsButHasNeverAnswered() {
        var watch = SetupWatch(totalMixWorked: false, rotoWorked: false)
        XCTAssertNil(watch.update(status: status(), totalMixRunning: false, now: 0))
        XCTAssertNil(watch.update(status: status(), totalMixRunning: true, now: 10))   // TotalMix FX started
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

    func testTheSetupAssistantOpensWhereItIsNeeded() {
        var status = BridgeStatus()
        status.listening = true
        let steps = SetupChecklist.steps(status: status, settings: BridgeSettings())
        XCTAssertEqual(steps[SetupChecklist.startIndex(of: steps)].id, "version", "the first step not done: TotalMix FX isn't running")
        XCTAssertEqual(steps[SetupChecklist.startIndex(of: steps, openFor: SetupWatch.Reason.rotoHandshake.stepID)].id, "roto",
                       "opened for a problem: that step")
        XCTAssertEqual(SetupChecklist.startIndex(of: steps, openFor: "launchcontrol"), SetupChecklist.startIndex(of: steps),
                       "a step that isn't there: the first one not done")
        for reason in [SetupWatch.Reason.portInUse, .totalMixNotAnswering, .totalMixTooOld] {
            XCTAssertNotNil(steps.first { $0.id == reason.stepID }, "\(reason) opens at a step that exists")
        }
        XCTAssertEqual(steps.map(\.id).suffix(4), ["livemode", "cue", "hide", "order"], "the notes come last, as their own pages")
        // The guide opens at the first step not done.
        var answering = status
        answering.totalMixAnswering = true
        let skipping = SetupChecklist.steps(status: answering, settings: BridgeSettings(), totalMixRunning: true,
                                            totalMixVersion: "2.10 (1)")
        let ids = skipping.map(\.id)
        let port = ids.firstIndex(of: "port")!, version = ids.firstIndex(of: "version")!
        XCTAssertEqual(skipping[port].state, .done)
        XCTAssertEqual(skipping[version].state, .done)
        XCTAssertEqual(SetupChecklist.startIndex(of: skipping), ids.firstIndex(of: "channels"),
                       "the first step not done: TotalMix FX answered, but no channels yet")
        XCTAssertFalse(skipping.contains { $0.state == .done && $0.detail.isEmpty }, "a done page says what was checked")
        XCTAssertFalse(steps.first { $0.id == "hide" }!.detail.contains("send row"),
                       "no Launch Control tip before a Launch Control is chosen")
        status.launchControlName = "Launch Control XL 3"
        let withLaunchControl = SetupChecklist.steps(status: status, settings: BridgeSettings())
        XCTAssertTrue(withLaunchControl.first { $0.id == "hide" }!.detail.contains("send row"))
        var launchControlOnly = status
        launchControlOnly.rotoEnabled = false
        XCTAssertNil(SetupChecklist.steps(status: launchControlOnly, settings: BridgeSettings()).first { $0.id == "meters" },
                     "no meters step for a Launch Control: it shows no meters")
        XCTAssertEqual(withLaunchControl[SetupChecklist.startIndex(of: withLaunchControl,
                                                                   openFor: SetupWatch.Reason.launchControlNotConnecting.stepID)].id,
                       "launchcontrol", "a Launch Control problem opens at its step")
    }

    func testTheHardwareControllerIsFoundByItsPortNames() {
        func sources(_ names: String...) -> [MIDIEndpointInfo] {
            names.enumerated().map { MIDIEndpointInfo(name: $1, uniqueID: Int32($0)) }
        }
        typealias D = DetectedController
        let none = sources("IAC Driver Bus 1", "Digiface AES")
        XCTAssertEqual(D.found(among: none, rotoPortName: "Roto"), [])
        let xl3 = sources("IAC Driver Bus 1", "LCXL3 1 MIDI Out", "LCXL3 1 DAW Out")
        XCTAssertEqual(D.found(among: xl3, rotoPortName: "Roto"), [.launchControl(.xl3)])
        let both = sources("Roto-Control", "LC3 1 DAW Out")
        XCTAssertEqual(D.found(among: both, rotoPortName: "Roto"), [.roto, .launchControl(.lc3)])

        XCTAssertEqual(D.switchTarget(chosen: .roto, found: [.launchControl(.xl3)]), .launchControl(.xl3),
                       "the Roto-Control isn't plugged in and only an XL 3 is: switch")
        XCTAssertNil(D.switchTarget(chosen: .launchControl(.xl3), found: [.launchControl(.xl3)]), "already chosen")
        XCTAssertNil(D.switchTarget(chosen: .roto, found: []), "nothing plugged in")
        XCTAssertNil(D.switchTarget(chosen: .launchControl(.xl3), found: [.roto, .launchControl(.lc3)]),
                     "several: the user chooses")
        XCTAssertNil(D.switchTarget(chosen: .roto, found: [.roto, .launchControl(.lc3)]), "the chosen one is there")
    }

    func testDoneStepsKeepTheirInstructions() {
        var status = BridgeStatus()
        status.listening = true
        status.totalMixAnswering = true
        status.levelsSeen = true
        let done = SetupChecklist.steps(status: status, settings: BridgeSettings())
        let totalMix = done.first { $0.id == "totalmix" }!
        XCTAssertEqual(totalMix.state, .done)
        XCTAssertTrue(totalMix.instructions.contains("Global OSC"), "how TotalMix FX was set up, on request")
        XCTAssertTrue(done.first { $0.id == "meters" }!.instructions.contains("Send Level Data"))
        let lines = totalMix.instructions.components(separatedBy: "\n")
        let images = lines.indices.filter { lines[$0].hasPrefix("[image:") }
        XCTAssertEqual(images.map { lines[$0] }, ["[image: totalmix-options-menu]", "[image: totalmix-osc-tab]",
                                                  "[image: totalmix-osc-details]"])
        XCTAssertTrue(lines[images[0] - 1].hasPrefix("2."), "each screenshot after the steps it shows")
        XCTAssertTrue(lines[images[1] - 1].hasPrefix("7."))
        XCTAssertTrue(lines[images[2] - 1].hasPrefix("8."))
        status.totalMixAnswering = false
        let waiting = SetupChecklist.steps(status: status, settings: BridgeSettings()).first { $0.id == "totalmix" }!
        XCTAssertEqual(waiting.detail, totalMix.instructions, "the same text as before it was done")
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

/// Layouts reported by the engine, collected across threads.
private final class SavedLayouts: @unchecked Sendable {
    private let lock = NSLock()
    private var layouts: [PerformanceLayout] = []
    func append(_ layout: PerformanceLayout) { lock.lock(); layouts.append(layout); lock.unlock() }
    var all: [PerformanceLayout] { lock.lock(); defer { lock.unlock() }; return layouts }
}

/// The send rows the engine reported, for a test.
private final class SavedRows: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [(LaunchControlModel, [Int?])] = []
    func append(_ layout: LaunchControlModel, _ choices: [Int?]) { lock.lock(); rows.append((layout, choices)); lock.unlock() }
    var all: [(LaunchControlModel, [Int?])] { lock.lock(); defer { lock.unlock() }; return rows }
}
