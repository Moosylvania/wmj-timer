import Foundation

public struct Credentials: Sendable {
    public var baseURL: URL       // {wmjURL}/api/beta1
    public var companyToken: String
    public var userToken: String

    public init?(wmjURL: String, companyToken: String, userToken: String) {
        let trimmed = wmjURL.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        guard !trimmed.isEmpty, !companyToken.isEmpty, !userToken.isEmpty,
              let url = URL(string: trimmed + "/api/beta1") else { return nil }
        self.baseURL = url
        self.companyToken = companyToken
        self.userToken = userToken
    }
}

public final class APIClient: Sendable {
    let credentialsProvider: @Sendable () -> Credentials?

    public init(credentialsProvider: @escaping @Sendable () -> Credentials?) {
        self.credentialsProvider = credentialsProvider
    }

    // MARK: - Endpoints

    public func projects(search: String = "") async throws -> [Project] {
        var query: [URLQueryItem] = []
        if !search.isEmpty {
            query = [.init(name: "searchFor", value: search),
                     .init(name: "searchField", value: "projectname")]
        }
        let list: Envelope<ProjectList> = try await get("projects", query: query)
        return list.data.project
    }

    public func tasks(projectKey: String) async throws -> [WMJTask] {
        let list: Envelope<TaskList> = try await get("tasks", query: [
            .init(name: "projectKey", value: projectKey),
            .init(name: "includeTaskUser", value: "true"),
        ])
        return list.data.task
    }

    public func services() async throws -> [Service] {
        let list: Envelope<ServiceList> = try await get("services", query: [])
        return list.data.service.sorted { $0.description < $1.description }
    }

    public func submit(_ entry: TimeEntry) async throws {
        try await sendTime(method: "POST", body: JSONEncoder().encode([entry]))
    }

    /// Entries already on the user's timesheet for one day (the UserToken
    /// scopes the query to the current user).
    public func timeEntries(on date: Date) async throws -> [TimesheetEntry] {
        // A timesheet can span more than the requested day — trust each
        // entry's own workDate ("2026-07-31T00:00:00", no timezone), compared
        // as a plain yyyy-MM-dd prefix to avoid timezone math entirely.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let dayPrefix = fmt.string(from: date)
        return try await timesheetEntries(start: date, end: date)
            .filter { $0.workDate.hasPrefix(dayPrefix) }
    }

    /// Who the UserToken belongs to and what they've logged lately, from their
    /// own timesheets — the only "membership" signal the API exposes without
    /// admin-only endpoints (/users, /employees/search are permission-gated).
    /// `userKey` matches `TaskUser.userKey` on task assignments.
    public func recentActivity(lookbackDays: Int = 90) async throws
        -> (userKey: String?, projectKeys: [String]) {
        let entries = try await timesheetEntries(
            start: Date().addingTimeInterval(-Double(lookbackDays) * 86_400), end: Date())
        var seen = Set<String>()
        let projectKeys = entries.compactMap(\.projectKey)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return (entries.compactMap(\.userKey).first { !$0.isEmpty }, projectKeys)
    }

    private func timesheetEntries(start: Date, end: Date) async throws -> [TimesheetEntry] {
        do {
            let list: Envelope<TimesheetList> = try await get("time", query: [
                .init(name: "startDate", value: TimeEntry.apiDateString(start)),
                .init(name: "endDate", value: TimeEntry.apiDateString(end)),
                .init(name: "includeTime", value: "1"),
            ])
            return list.data.timesheet.flatMap { $0.timeEntries ?? [] }
        } catch let APIError.http(status: 400, description: description)
            where description.localizedCaseInsensitiveContains("no results") {
            // The API 400s on an empty range ("Your search returned no
            // results. Please try again.") — that's an empty timesheet, not
            // an error.
            return []
        }
    }

    /// Replaces an existing entry's hours (merge-on-submit computes the new total).
    public func updateTime(timeKey: String, hours: Double) async throws {
        let body = try JSONEncoder().encode([["timeKey": timeKey, "hours": String(format: "%g", hours)]])
        try await sendTime(method: "PUT", body: body)
    }

    private func sendTime(method: String, body: Data) async throws {
        let data = try await send(path: "time", method: method, body: body)
        // Success looks like {"success":[{...}]}; anything else is a failure worth surfacing.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? [Any], !success.isEmpty else {
            Self.log("\(method) /time unexpected body\n\(String(data: data.prefix(4096), encoding: .utf8) ?? "")")
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.message
            throw APIError.badResponse(message ?? "details in ~/Library/Logs/WmjQuickTimer.log")
        }
    }

    // MARK: - Plumbing

    func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let data = try await send(path: path, method: "GET", query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Self.log("GET /\(path) decode failure: \(error)\n\(String(data: data.prefix(4096), encoding: .utf8) ?? "")")
            throw APIError.badResponse("details in ~/Library/Logs/WmjQuickTimer.log")
        }
    }

    func send(path: String, method: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        guard let creds = credentialsProvider() else { throw APIError.notConfigured }
        var components = URLComponents(url: creds.baseURL.appending(path: path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(creds.companyToken, forHTTPHeaderField: "APIAccessToken")
        request.setValue(creds.userToken, forHTTPHeaderField: "UserToken")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data.prefix(4096), encoding: .utf8) ?? ""
            Self.log("HTTP \(status) \(method) /\(path)\n\(body)")
            let bodyError = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            let description = bodyError?.message ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            if status == 403, description.localizedCaseInsensitiveContains("not enabled") {
                throw APIError.accessNotEnabled
            }
            throw APIError.http(status: status, description: description)
        }
        return data
    }

    /// Full API failures land in ~/Library/Logs/WmjQuickTimer.log — the UI
    /// truncates error bodies, this file never does. Tokens are never written.
    public static func log(_ message: String) {
        let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/WmjQuickTimer.log")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
