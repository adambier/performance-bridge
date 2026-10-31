import XCTest
import OSCCodec
import TotalMixOSC
import SurfaceCore
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
}
