import XCTest
@testable import WmjQuickTimerCore

final class TimeMathTests: XCTestCase {
    func testQuarterRounding() {
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 0), 0.25)      // min clamp
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 180), 0.25)    // 3 min → 0.25
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 600), 0.25)    // 10 min → 0.25
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 900), 0.25)    // exactly 15 min stays 0.25
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 901), 0.5)     // a second over rounds up
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 1360), 0.5)    // ~22.7 min → 0.5
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 3600), 1.0)
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 3600 + 60), 1.25)
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 8 * 3600), 8.0)
        XCTAssertEqual(TimeMath.quarterHours(fromSeconds: 9 * 3600), 9.0) // timer has no 8h cap
    }

    func testQuickLogValidation() {
        XCTAssertTrue(TimeMath.isValidQuickLogHours(0.25))
        XCTAssertTrue(TimeMath.isValidQuickLogHours(0.5))
        XCTAssertTrue(TimeMath.isValidQuickLogHours(7.75))
        XCTAssertTrue(TimeMath.isValidQuickLogHours(8.0))
        XCTAssertFalse(TimeMath.isValidQuickLogHours(0))
        XCTAssertFalse(TimeMath.isValidQuickLogHours(0.1))
        XCTAssertFalse(TimeMath.isValidQuickLogHours(0.3))
        XCTAssertFalse(TimeMath.isValidQuickLogHours(8.25))
        XCTAssertFalse(TimeMath.isValidQuickLogHours(-1))
    }
}
