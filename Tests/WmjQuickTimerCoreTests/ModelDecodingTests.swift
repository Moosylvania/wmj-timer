import XCTest
@testable import WmjQuickTimerCore

final class ModelDecodingTests: XCTestCase {
    func testTaskIDDecodesFromNumber() throws {
        let json = Data(#"{"taskKey":"K1","taskID":42.0,"taskName":"Dev"}"#.utf8)
        let task = try JSONDecoder().decode(WMJTask.self, from: json)
        XCTAssertEqual(task.taskID, "42")
    }

    func testTaskIDDecodesFromString() throws {
        let json = Data(#"{"taskKey":"K1","taskID":"42","taskName":"Dev"}"#.utf8)
        let task = try JSONDecoder().decode(WMJTask.self, from: json)
        XCTAssertEqual(task.taskID, "42")
    }

    func testTaskIDDecodesFromDottedString() throws {
        let json = Data(#"{"taskKey":"K1","taskID":"2.1.1","taskName":"Dev"}"#.utf8)
        let task = try JSONDecoder().decode(WMJTask.self, from: json)
        XCTAssertEqual(task.taskID, "2.1.1")
    }
}
