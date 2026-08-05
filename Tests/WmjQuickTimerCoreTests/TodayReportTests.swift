import XCTest
@testable import WmjQuickTimerCore

final class TodayReportTests: XCTestCase {
    func testBuildResolvesNamesWithFallbacks() {
        let projects = [Project(projectKey: "p1", projectNumber: "ACME-1", projectName: "Website", clientName: "Acme")]
        let services = [Service(serviceCode: "DEV", description: "Development")]
        let tasks = [WMJTask(taskKey: "t1", taskID: "30", taskName: "Build")]
        let entries = [
            // Fully resolvable — service code lowercased like the real API.
            TimesheetEntry(timeKey: "e1", actualHours: 1.5, projectNumber: "ACME-1",
                           taskID: "30", serviceCode: "dev", workDate: "2026-08-05T00:00:00", projectKey: "p1"),
            // Unknown project/service, nil projectKey — raw values fall through.
            TimesheetEntry(timeKey: "e2", actualHours: 2, projectNumber: "MYST-9",
                           taskID: "2.1.1", serviceCode: "xx", workDate: "2026-08-05T00:00:00"),
            // 0-hour pre-start validation row — hidden.
            TimesheetEntry(timeKey: "e3", actualHours: 0, projectNumber: "ACME-1",
                           taskID: "30", serviceCode: "dev", workDate: "2026-08-05T00:00:00", projectKey: "p1"),
        ]

        let rows = TodayRow.build(entries: entries, projects: projects,
                                  services: services, tasksByProject: ["p1": tasks])

        XCTAssertEqual(rows, [
            TodayRow(id: "e1", projectName: "Website", taskName: "Build",
                     serviceName: "Development", hours: 1.5),
            TodayRow(id: "e2", projectName: "MYST-9", taskName: "2.1.1",
                     serviceName: "xx", hours: 2),
        ])
    }
}
