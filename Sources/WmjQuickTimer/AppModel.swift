import Foundation
import Observation
import WmjQuickTimerCore

@Observable @MainActor
final class AppModel {
    // MARK: Settings (tokens live in the Keychain, the rest in UserDefaults)

    var wmjURL: String = UserDefaults.standard.string(forKey: "wmjURL") ?? "" {
        didSet { UserDefaults.standard.set(wmjURL, forKey: "wmjURL") }
    }
    var email: String = UserDefaults.standard.string(forKey: "email") ?? "" {
        didSet { UserDefaults.standard.set(email, forKey: "email") }
    }
    var defaultServiceCode: String = UserDefaults.standard.string(forKey: "defaultServiceCode") ?? "" {
        didSet { UserDefaults.standard.set(defaultServiceCode, forKey: "defaultServiceCode") }
    }
    /// userID confirmed via employees/search; used instead of the raw email once known.
    var resolvedUserID: String = UserDefaults.standard.string(forKey: "resolvedUserID") ?? "" {
        didSet { UserDefaults.standard.set(resolvedUserID, forKey: "resolvedUserID") }
    }

    /// Stored, not computed: the Keychain isn't observable, so the menu would
    /// never notice tokens being saved.
    private(set) var isConfigured = false

    /// Single write path for credentials, so `isConfigured` can't go stale.
    func saveCredentials(url: String, email: String, companyToken: String, userToken: String) {
        wmjURL = url
        self.email = email
        Keychain.save(Keychain.Tokens(company: companyToken, user: userToken))
        isConfigured = ![url, email, companyToken, userToken].contains(where: \.isEmpty)
    }

    // MARK: Data

    let api = APIClient {
        let tokens = Keychain.tokens()
        return Credentials(wmjURL: UserDefaults.standard.string(forKey: "wmjURL") ?? "",
                           companyToken: tokens?.company ?? "",
                           userToken: tokens?.user ?? "")
    }
    var projects: [Project] = []
    var services: [Service] = []
    var loadError: String?
    @ObservationIgnored private var loading = false

    // MARK: Timer

    var timer = TimerState() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(timer), forKey: "timerState") }
    }
    var now = Date()
    @ObservationIgnored private var tick: Timer?

    init() {
        isConfigured = !wmjURL.isEmpty && !email.isEmpty
            && Keychain.tokens() != nil
        if let data = UserDefaults.standard.data(forKey: "timerState"),
           let saved = try? JSONDecoder().decode(TimerState.self, from: data) {
            timer = saved
        }
        syncTick()
    }

    func startTimer(_ selection: TaskSelection) {
        timer.start(selection)
        syncTick()
    }

    func stopTimer() {
        timer.stop()
        syncTick()
    }

    func resumeTimer() {
        timer.resume()
        syncTick()
    }

    func discardTimer() {
        timer.discard()
        syncTick()
    }

    /// The 1s tick only exists while the timer runs; elapsed derives from wall clock.
    private func syncTick() {
        if timer.isRunning, tick == nil {
            tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in self.now = Date() }
            }
        } else if !timer.isRunning {
            tick?.invalidate()
            tick = nil
        }
        now = Date()
    }

    // MARK: Actions

    func refresh() async {
        guard isConfigured, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            if services.isEmpty { services = try await api.services() }
            projects = try await api.projects().sorted { $0.projectName < $1.projectName }
            loadError = nil
        } catch is CancellationError {
            // View went away mid-fetch — not something to show the user.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Post time using the email as userID; on rejection, resolve the real
    /// userID via employees/search and retry once.
    func submitTime(selection: TaskSelection, hours: Double, comments: String = "") async throws {
        func entry(_ userID: String) -> TimeEntry {
            TimeEntry(userID: userID, hours: hours, projectNumber: selection.projectNumber,
                      taskID: selection.taskID, serviceCode: selection.serviceCode,
                      workDate: Date(), comments: comments)
        }
        let userID = resolvedUserID.isEmpty ? email.lowercased() : resolvedUserID
        do {
            try await api.submit(entry(userID))
        } catch {
            guard let employee = try? await api.employee(email: email),
                  employee.userID != userID else { throw error }
            try await api.submit(entry(employee.userID))
            resolvedUserID = employee.userID
        }
    }

    func submitTimer() async throws {
        guard let selection = timer.selection else { return }
        try await submitTime(selection: selection, hours: timer.submittableHours())
        discardTimer()
    }

    /// Settings "Verify Connection": confirms tokens and captures the user's
    /// real userID and default service code.
    func verifyConnection() async throws -> Employee {
        guard let employee = try await api.employee(email: email) else {
            throw APIError.badResponse("No employee found for \(email)")
        }
        resolvedUserID = employee.userID
        if defaultServiceCode.isEmpty { defaultServiceCode = employee.defaultServiceCode }
        return employee
    }

    // MARK: Formatting

    func elapsedText(short: Bool) -> String {
        let seconds = Int(timer.elapsed(now: now))
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return short ? String(format: "%d:%02d", h, m) : String(format: "%d:%02d:%02d", h, m, s)
    }
}
