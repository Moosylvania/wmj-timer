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

    public func employee(email: String) async throws -> Employee? {
        let list: Envelope<EmployeeList> = try await get("employees/search", query: [
            .init(name: "email", value: email),
        ])
        return list.data.employee.first
    }

    public func submit(_ entry: TimeEntry) async throws {
        let body = try JSONEncoder().encode([entry])
        let data = try await send(path: "time", method: "POST", body: body)
        // Success looks like {"success":[{...}]}; anything else is a failure worth surfacing.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? [Any], !success.isEmpty else {
            let text = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw APIError.badResponse(text)
        }
    }

    // MARK: - Plumbing

    func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let data = try await send(path: path, method: "GET", query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.badResponse(String(describing: error))
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
            let bodyError = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            let description = bodyError?.description ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            if status == 403, description.localizedCaseInsensitiveContains("not enabled") {
                throw APIError.accessNotEnabled
            }
            throw APIError.http(status: status, description: description)
        }
        return data
    }
}
