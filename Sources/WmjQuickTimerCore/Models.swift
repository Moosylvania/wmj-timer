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

/// One row of a task's `taskUser` array (`includeTaskUser=true`) — an
/// assignment. `userKey` matches the `userKey` on the user's own timesheet
/// entries, which is how the app identifies "me" without admin-only endpoints.
public struct TaskUser: Codable, Hashable, Sendable {
    public var userKey: String
    public var userName: String?
    public var serviceCode: String?

    public init(userKey: String, userName: String? = nil, serviceCode: String? = nil) {
        self.userKey = userKey
        self.userName = userName
        self.serviceCode = serviceCode
    }

    enum CodingKeys: String, CodingKey {
        case userKey, userName, serviceCode
    }
}

public struct WMJTask: Codable, Identifiable, Hashable, Sendable {
    public var taskKey: String
    /// Stored as a string: the API returns a number for most projects but
    /// strings like "2.1.1" for some, and POST /time takes it as a string anyway.
    public var taskID: String
    public var taskName: String
    /// Schedule indicator (1/2/3 ≈ upcoming/current/late), NOT open vs closed —
    /// completion lives in `percComp`/`completedByDate`.
    public var taskStatus: Double?
    public var percComp: Double?
    /// "1/1/1900 12:00:00 AM" (or empty) means never completed.
    public var completedByDate: String?
    public var taskUsers: [TaskUser]

    public var id: String { taskKey }

    /// Not completed — time can still be charged to it.
    public var isActive: Bool {
        guard percComp != 100 else { return false }
        guard let date = completedByDate, !date.isEmpty else { return true }
        return date.hasPrefix("1/1/1900")
    }

    /// Unassigned tasks stay available (some setups allow logging to any task
    /// on a member project); an unknown userKey means we can't tell — show it.
    public func isAvailable(to userKey: String?) -> Bool {
        taskUsers.isEmpty || userKey == nil || taskUsers.contains { $0.userKey == userKey }
    }

    public init(taskKey: String, taskID: String, taskName: String, taskStatus: Double? = nil,
                percComp: Double? = nil, completedByDate: String? = nil, taskUsers: [TaskUser] = []) {
        self.taskKey = taskKey
        self.taskID = taskID
        self.taskName = taskName
        self.taskStatus = taskStatus
        self.percComp = percComp
        self.completedByDate = completedByDate
        self.taskUsers = taskUsers
    }

    enum CodingKeys: String, CodingKey {
        case taskKey, taskID, taskName, taskStatus, percComp, completedByDate
        case taskUsers = "taskUser"
    }

    /// Accept `taskID` as a number (42 → "42") or any string ("2.1.1").
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskKey = try c.decode(String.self, forKey: .taskKey)
        taskName = try c.decode(String.self, forKey: .taskName)
        taskStatus = try? c.decode(Double.self, forKey: .taskStatus)
        percComp = try? c.decode(Double.self, forKey: .percComp)
        completedByDate = try? c.decode(String.self, forKey: .completedByDate)
        taskUsers = (try? c.decode([TaskUser].self, forKey: .taskUsers)) ?? []
        if let string = try? c.decode(String.self, forKey: .taskID) {
            taskID = string
        } else {
            let number = try c.decode(Double.self, forKey: .taskID)
            taskID = number == number.rounded() ? String(Int(number)) : String(number)
        }
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
    /// The entry's owner — timesheets are UserToken-scoped, so this is how the
    /// app learns its own userKey (matches `TaskUser.userKey`).
    public var userKey: String?
    public var projectKey: String?

    public init(timeKey: String, actualHours: Double, projectNumber: String,
                taskID: String, serviceCode: String, workDate: String,
                userKey: String? = nil, projectKey: String? = nil) {
        self.timeKey = timeKey
        self.actualHours = actualHours
        self.projectNumber = projectNumber
        self.taskID = taskID
        self.serviceCode = serviceCode
        self.workDate = workDate
        self.userKey = userKey
        self.projectKey = projectKey
    }

    enum CodingKeys: String, CodingKey {
        case timeKey, actualHours, projectNumber, taskID, serviceCode, workDate, userKey, projectKey
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

/// Workamajig error bodies come in two shapes:
/// `{"status":…,"description":…}` and
/// `{"logid":…,"errors":[{"error":[{"message":…,"status":…}]}]}` — plus the
/// occasional `{"errors":["-3"]}` with bare strings. Everything is optional so
/// any of them decodes.
struct APIErrorBody: Decodable {
    struct ErrorGroup: Decodable {
        var messages: [String] = []

        init(from decoder: Decoder) throws {
            struct Item: Decodable { var message: String? }
            struct Keyed: Decodable { var error: [Item]? }
            if let keyed = try? decoder.singleValueContainer().decode(Keyed.self) {
                messages = (keyed.error ?? []).compactMap(\.message)
            } else if let text = try? decoder.singleValueContainer().decode(String.self) {
                messages = [text]
            }
        }
    }

    var status: Int?
    var description: String?
    var errors: [ErrorGroup]?

    /// The human-readable sentence(s), whichever shape arrived.
    var message: String? {
        let nested = (errors ?? []).flatMap(\.messages).filter { !$0.isEmpty }
        if !nested.isEmpty { return nested.joined(separator: " ") }
        return description
    }
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
