import Foundation

// Field casing differs per Workamajig module (PascalCase for projects/services,
// camelCase for tasks/employees), so every model spells out its CodingKeys.

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var projectKey: String
    public var projectNumber: String
    public var projectName: String
    public var clientName: String

    public var id: String { projectKey }

    public init(projectKey: String, projectNumber: String, projectName: String, clientName: String) {
        self.projectKey = projectKey
        self.projectNumber = projectNumber
        self.projectName = projectName
        self.clientName = clientName
    }

    enum CodingKeys: String, CodingKey {
        case projectKey = "ProjectKey"
        case projectNumber = "ProjectNumber"
        case projectName = "ProjectName"
        case clientName = "ClientName"
    }
}

public struct WMJTask: Codable, Identifiable, Hashable, Sendable {
    public var taskKey: String
    public var taskID: Double
    public var taskName: String
    public var taskStatus: Double?

    public var id: String { taskKey }
    /// POST /time wants the integer task ID as a string ("1"), not 1.0.
    public var taskIDString: String { String(Int(taskID)) }

    public init(taskKey: String, taskID: Double, taskName: String, taskStatus: Double? = nil) {
        self.taskKey = taskKey
        self.taskID = taskID
        self.taskName = taskName
        self.taskStatus = taskStatus
    }

    enum CodingKeys: String, CodingKey {
        case taskKey, taskID, taskName, taskStatus
    }
}

public struct Service: Codable, Identifiable, Hashable, Sendable {
    public var serviceCode: String
    public var description: String

    public var id: String { serviceCode }

    public init(serviceCode: String, description: String) {
        self.serviceCode = serviceCode
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case serviceCode = "ServiceCode"
        case description = "Description"
    }
}

public struct TimeEntry: Codable, Sendable {
    public var userID: String
    public var hours: String
    public var projectNumber: String
    public var taskID: String
    public var serviceCode: String
    public var workDate: String
    public var comments: String
    public var overtime = "0"

    public init(userID: String, hours: Double, projectNumber: String, taskID: String,
                serviceCode: String, workDate: Date, comments: String = "") {
        self.userID = userID
        self.hours = String(format: "%g", hours)
        self.projectNumber = projectNumber
        self.taskID = taskID
        self.serviceCode = serviceCode
        self.workDate = Self.apiDateString(workDate)
        self.comments = comments
    }

    /// The M/d/yyyy (en_US_POSIX) form the time endpoints expect.
    public static func apiDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "M/d/yyyy"
        return fmt.string(from: date)
    }
}

/// A row already on the timesheet (from `GET /time?includeTime=1`) — what
/// merge-on-submit matches against. camelCase like the tasks module, but
/// `taskID` is a string here, not a Double.
public struct TimesheetEntry: Codable, Sendable {
    public var timeKey: String
    public var actualHours: Double
    public var projectNumber: String
    public var taskID: String
    public var serviceCode: String
    public var workDate: String   // "2026-07-31T00:00:00"

    public init(timeKey: String, actualHours: Double, projectNumber: String,
                taskID: String, serviceCode: String, workDate: String) {
        self.timeKey = timeKey
        self.actualHours = actualHours
        self.projectNumber = projectNumber
        self.taskID = taskID
        self.serviceCode = serviceCode
        self.workDate = workDate
    }

    enum CodingKeys: String, CodingKey {
        case timeKey, actualHours, projectNumber, taskID, serviceCode, workDate
    }
}

public extension [TimesheetEntry] {
    /// The row a submission should merge into: same project, task, and
    /// service (Workamajig lowercases service codes on the timesheet).
    func firstMatch(_ selection: TaskSelection) -> TimesheetEntry? {
        first {
            $0.projectNumber == selection.projectNumber
                && $0.taskID == selection.taskID
                && $0.serviceCode.caseInsensitiveCompare(selection.serviceCode) == .orderedSame
        }
    }
}

// MARK: - Response envelopes

struct Envelope<Payload: Decodable>: Decodable {
    var data: Payload
}

struct ProjectList: Decodable { var project: [Project] }
struct TimesheetList: Decodable {
    struct Timesheet: Decodable {
        var timeEntries: [TimesheetEntry]?
        enum CodingKeys: String, CodingKey { case timeEntries = "TimeEntries" }
    }
    var timesheet: [Timesheet]
}
struct TaskList: Decodable { var task: [WMJTask] }
struct ServiceList: Decodable { var service: [Service] }

struct APIErrorBody: Decodable {
    var status: Int?
    var description: String?
}

public enum APIError: LocalizedError, Equatable {
    case notConfigured
    case accessNotEnabled
    case http(status: Int, description: String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Open Settings and enter your Workamajig URL, tokens, and email."
        case .accessNotEnabled:
            "Your Workamajig admin must enable API access for your user account."
        case .http(let status, let description):
            "Workamajig error (\(status)): \(description)"
        case .badResponse(let detail):
            "Unexpected response from Workamajig: \(detail)"
        }
    }
}
