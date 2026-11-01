import XCTest
@testable import TotalMixOSC

final class TotalMixVersionTests: XCTestCase {
    func testReadsRMEsVersionStrings() {
        XCTAssertEqual(TotalMixVersion("2.10 (1)"), TotalMixVersion(major: 2, hundredths: 10))
        XCTAssertEqual(TotalMixVersion("2.1"), TotalMixVersion(major: 2, hundredths: 10))
        XCTAssertEqual(TotalMixVersion("1.96"), TotalMixVersion(major: 1, hundredths: 96))
        XCTAssertEqual(TotalMixVersion("Version 2.11 RC2"), TotalMixVersion(major: 2, hundredths: 11))
        XCTAssertEqual(TotalMixVersion("2.1 beta 2"), TotalMixVersion(major: 2, hundredths: 10))
        XCTAssertEqual(TotalMixVersion("2.105"), TotalMixVersion(major: 2, hundredths: 10))
        XCTAssertNil(TotalMixVersion(""))
        XCTAssertNil(TotalMixVersion("TotalMix FX"))
        XCTAssertNil(TotalMixVersion("2."))
    }

    func testGlobalOSCStartsAt2Point1() {
        XCTAssertTrue(TotalMixVersion("2.10 (1)")!.supportsGlobalOSC)
        XCTAssertTrue(TotalMixVersion("2.1 RC1")!.supportsGlobalOSC)
        XCTAssertTrue(TotalMixVersion("2.11")!.supportsGlobalOSC)
        XCTAssertTrue(TotalMixVersion("3.0")!.supportsGlobalOSC)
        XCTAssertFalse(TotalMixVersion("1.99")!.supportsGlobalOSC)
        XCTAssertFalse(TotalMixVersion("1.96")!.supportsGlobalOSC)
        XCTAssertFalse(TotalMixVersion("2.0")!.supportsGlobalOSC)
    }

    func testOrderAndDescription() {
        XCTAssertLessThan(TotalMixVersion("1.99")!, TotalMixVersion("2.1")!)
        XCTAssertLessThan(TotalMixVersion("2.10")!, TotalMixVersion("2.11")!)
        XCTAssertEqual(TotalMixVersion("2.1")!.description, "2.10")
        XCTAssertEqual(TotalMixVersion("3.05")!.description, "3.05")
    }
}
