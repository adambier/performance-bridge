import XCTest
@testable import TotalMixOSC

final class FaderCurveTests: XCTestCase {
    /// RME's decimal form of the curve (protocol document, revision 2026-07-21, sheet "Fader curve"),
    /// kept here only to check that the fractions in FaderCurve agree with it.
    private func rmeGain(_ position: Double) -> Double {
        let step = position * 1023
        if step >= 649 { return step * 0.0320855615 - 26.8235294118 }
        return step * step * (-1 / 11033.0) + step * 0.1497326203 - 65
    }

    private func rmePosition(_ gain: Double) -> Double {
        let step = gain >= -6 ? (gain + 26.8235294118) * (1 / 0.0320855615) : 826 - (-34869 - 11033 * gain).squareRoot()
        return min(max(step / 1023, 0), 1)
    }

    func testAgreesWithRMEsDecimalConstants() {
        for step in 0...1023 {
            let position = Double(step) / 1023
            let ours = FaderCurve.gainDB(position: position)
            let theirs = rmeGain(position)
            if theirs < -64.9 {
                XCTAssertNil(ours, "step \(step)")
            } else {
                XCTAssertEqual(ours ?? .nan, theirs, accuracy: 1e-7, "step \(step)")
            }
        }
        for tenth in -650...60 {
            let gain = Double(tenth) / 10
            XCTAssertEqual(FaderCurve.position(gainDB: gain), rmePosition(gain), accuracy: 1e-9, "\(gain) dB")
        }
    }

    func testLandmarks() {
        XCTAssertEqual(FaderCurve.gainDB(position: 1) ?? .nan, 6, accuracy: 1e-12)
        XCTAssertEqual(FaderCurve.gainDB(position: 649 / 1023) ?? .nan, -6, accuracy: 1e-12)
        XCTAssertNil(FaderCurve.gainDB(position: 0))
        XCTAssertEqual(FaderCurve.unityPosition * 1023, 836, accuracy: 1e-9)
        XCTAssertEqual(FaderCurve.position(gainDB: -6) * 1023, 649, accuracy: 1e-9)
        XCTAssertEqual(FaderCurve.position(gainDB: -65), 0)
        XCTAssertEqual(FaderCurve.position(gainDB: nil), 0)
        XCTAssertEqual(FaderCurve.position(gainDB: 12), 1)
    }

    func testSegmentsMeetAtTheKnee() {
        let below = FaderCurve.gainDB(position: (649 - 1e-9) / 1023) ?? .nan
        let above = FaderCurve.gainDB(position: 649 / 1023) ?? .nan
        XCTAssertEqual(below, above, accuracy: 1e-6)
    }

    func testRoundTripAcrossTheRange() {
        for step in 1...1023 {
            let position = Double(step) / 1023
            guard let gain = FaderCurve.gainDB(position: position) else { continue }
            XCTAssertEqual(FaderCurve.position(gainDB: gain), position, accuracy: 1e-9, "step \(step)")
        }
    }

    func testClampsOutOfRangePositions() {
        XCTAssertEqual(FaderCurve.gainDB(position: 1.5), FaderCurve.gainDB(position: 1))
        XCTAssertNil(FaderCurve.gainDB(position: -0.1))
    }
}
