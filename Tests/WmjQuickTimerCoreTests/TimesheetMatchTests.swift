import XCTest
@testable import WmjQuickTimerCore

final class TimesheetMatchTests: XCTestCase {
    private func entry(project: String = "26-Moose-0130", task: String = "1",
                       service: String = "chfarc", hours: Double = 0.25) -> TimesheetEntry {
        TimesheetEntry(timeKey: "k-\(project)-\(task)-\(service)", actualHours: hours,
                       projectNumber: project, taskID: task, serviceCode: service,
                       workDate: "2026-07-31T00:00:00")
    }

    private func selection(project: String = "26-Moose-0130", task: String = "1",
                           service: String = "CHFARC") -> TaskSelection {
        TaskSelection(projectNumber: project, projectName: "Push Goal Work",
                      taskID: task, taskName: "Task", serviceCode: service)
    }

    func testMatchesSameRowCaseInsensitiveService() {
        // Workamajig lowercases service codes on the timesheet; the picker's
        // code may be uppercase — still the same row.
        let match = [entry()].firstMatch(selection())
        XCTAssertEqual(match?.timeKey, "k-26-Moose-0130-1-chfarc")
        XCTAssertEqual(match?.actualHours, 0.25)
    }

    func testNoMatchWhenAnyComponentDiffers() {
        let entries = [entry()]
        XCTAssertNil(entries.firstMatch(selection(project: "26-Moose-9999")))
        XCTAssertNil(entries.firstMatch(selection(task: "2")))
        XCTAssertNil(entries.firstMatch(selection(service: "DEV")))
    }

    func testPicksTheMatchingRowAmongMany() {
        let entries = [entry(task: "2"), entry(service: "dev"), entry(hours: 1.5)]
        XCTAssertEqual([entries].flatMap { $0 }.firstMatch(selection())?.actualHours, 1.5)
    }
}
