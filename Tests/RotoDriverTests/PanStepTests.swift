import XCTest
@testable import RotoDriver

final class PanStepTests: XCTestCase {
    func testThePanCenterStopIsCenter() {
        let stop = 8191.0 / 16383  // the 14 bits' nearest value under the middle
        XCTAssertEqual(RotoDriver.panInSteps(stop), 0.5, "C in TotalMix FX, as on the knob's screen")
        XCTAssertEqual(RotoDriver.panInSteps(8192.0 / 16383), 0.5)
    }

    func testPansLandOnHundredths() {
        XCTAssertEqual(RotoDriver.panInSteps(0), 0)
        XCTAssertEqual(RotoDriver.panInSteps(1), 1)
        XCTAssertEqual(RotoDriver.panInSteps(0.4951) * 2 - 1, -0.01, accuracy: 1e-12, "L1")
        XCTAssertEqual(RotoDriver.panInSteps(0.75) * 2 - 1, 0.5, accuracy: 1e-12, "R50")
    }
}
