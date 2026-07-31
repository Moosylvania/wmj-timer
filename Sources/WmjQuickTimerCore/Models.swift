import Foundation

// Field casing differs per Workamajig module (PascalCase for projects/services,
// camelCase for tasks/employees), so every model spells out its CodingKeys.

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var projectKey: String
    public var projectNumber: String
    public var projectName: String
    public var clientName: String

    public var id: String { projectKey }

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

    enum CodingKeys: String, CodingKey {
        case taskKey, taskID, taskName, taskStatus
    }
}

public struct Service: Codable, Identifiable, Hashable, Sendable {
    public var serviceCode: String
    public var description: String

    public var id: String { serviceCode }

    enum CodingKeys: String, CodingKey {
        case serviceCode = "ServiceCode"
        case description = "Description"
    }
}

public struct Employee: Codable, Sendable {
    public var userID: String
    public var email: String
    public var defaultServiceCode: String
    public var firstName: String
    public var lastName: String

    enum CodingKeys: String, CodingKey {
        case userID, email, defaultServiceCode, firstName, lastName
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
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "M/d/yyyy"
        self.workDate = fmt.string(from: workDate)
        self.comments = comments
    }
}

// MARK: - Response envelopes

struct Envelope<Payload: Decodable>: Decodable {
    var data: Payload
}

struct ProjectList: Decodable { var project: [Project] }
struct TaskList: Decodable { var task: [WMJTask] }
struct ServiceList: Decodable { var service: [Service] }
struct EmployeeList: Decodable { var employee: [Employee] }

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
