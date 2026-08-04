import XCTest
@testable import WmjQuickTimerCore

final class TaskFilterTests: XCTestCase {
    func testActiveWhenNotCompleted() {
        XCTAssertTrue(WMJTask(taskKey: "K", taskID: "1", taskName: "T").isActive)
        XCTAssertTrue(WMJTask(taskKey: "K", taskID: "1", taskName: "T",
                              percComp: 50, completedByDate: "1/1/1900 12:00:00 AM").isActive)
        XCTAssertTrue(WMJTask(taskKey: "K", taskID: "1", taskName: "T", completedByDate: "").isActive)
    }

    func testClosedByPercComp() {
        XCTAssertFalse(WMJTask(taskKey: "K", taskID: "1", taskName: "T", percComp: 100).isActive)
    }

    func testClosedByCompletedDate() {
        XCTAssertFalse(WMJTask(taskKey: "K", taskID: "1", taskName: "T",
                               completedByDate: "6/2/2026 12:00:00 AM").isActive)
    }

    func testAvailability() {
        let unassigned = WMJTask(taskKey: "K", taskID: "1", taskName: "T")
        let mine = WMJTask(taskKey: "K", taskID: "1", taskName: "T",
                           taskUsers: [TaskUser(userKey: "me"), TaskUser(userKey: "other")])
        let theirs = WMJTask(taskKey: "K", taskID: "1", taskName: "T",
                             taskUsers: [TaskUser(userKey: "other")])
        XCTAssertTrue(unassigned.isAvailable(to: "me"))
        XCTAssertTrue(mine.isAvailable(to: "me"))
        XCTAssertFalse(theirs.isAvailable(to: "me"))
        // Unknown userKey (never logged time) — can't tell, so don't hide.
        XCTAssertTrue(theirs.isAvailable(to: nil))
    }

    func testDecodesTaskUsersAndCompletion() throws {
        let json = Data("""
        {"taskKey":"K1","taskID":1.0,"taskName":"Dev","taskStatus":3.0,"percComp":25.0,
         "completedByDate":"1/1/1900 12:00:00 AM",
         "taskUser":[{"userKey":"U1","userName":"Joe Madden","serviceCode":"chfarc","actualHours":5.0}]}
        """.utf8)
        let task = try JSONDecoder().decode(WMJTask.self, from: json)
        XCTAssertEqual(task.taskUsers.map(\.userKey), ["U1"])
        XCTAssertTrue(task.isActive)
        XCTAssertTrue(task.isAvailable(to: "U1"))
        XCTAssertFalse(task.isAvailable(to: "U2"))
    }

    func testDecodesWithoutTaskUser() throws {
        let json = Data(#"{"taskKey":"K1","taskID":"2.1.1","taskName":"Dev"}"#.utf8)
        let task = try JSONDecoder().decode(WMJTask.self, from: json)
        XCTAssertEqual(task.taskUsers, [])
        XCTAssertTrue(task.isActive)
    }

    func testTimesheetEntryDecodesUserAndProjectKeys() throws {
        let json = Data("""
        {"timeKey":"T1","actualHours":1.5,"projectNumber":"26-X-1","taskID":"3",
         "serviceCode":"dev","workDate":"2026-07-31T00:00:00","userKey":"U1","projectKey":"P1"}
        """.utf8)
        let entry = try JSONDecoder().decode(TimesheetEntry.self, from: json)
        XCTAssertEqual(entry.userKey, "U1")
        XCTAssertEqual(entry.projectKey, "P1")
    }
}
