import Foundation
import Observation
import WmjQuickTimerCore

@Observable @MainActor
final class AppModel {
    /// `WMJ_DEMO=1` runs the UI on canned data for screenshots: no API calls,
    /// no Keychain reads, no UserDefaults writes. See AGENTS.md.
    static let demo = ProcessInfo.processInfo.environment["WMJ_DEMO"] == "1"

    // MARK: Settings (tokens live in the Keychain, the rest in UserDefaults)

    var wmjURL: String = UserDefaults.standard.string(forKey: "wmjURL") ?? "" {
        didSet { if !Self.demo { UserDefaults.standard.set(wmjURL, forKey: "wmjURL") } }
    }
    var email: String = UserDefaults.standard.string(forKey: "email") ?? "" {
        didSet { if !Self.demo { UserDefaults.standard.set(email, forKey: "email") } }
    }
    var defaultServiceCode: String = UserDefaults.standard.string(forKey: "defaultServiceCode") ?? "" {
        didSet { if !Self.demo { UserDefaults.standard.set(defaultServiceCode, forKey: "defaultServiceCode") } }
    }
    /// Stored, not computed: the Keychain isn't observable, so the menu would
    /// never notice tokens being saved.
    private(set) var isConfigured = false

    /// Single write path for credentials, so `isConfigured` can't go stale.
    func saveCredentials(url: String, email: String, companyToken: String, userToken: String) {
        // Accept the URL with or without a trailing slash — store it without.
        var url = url.trimmingCharacters(in: .whitespaces)
        while url.hasSuffix("/") { url.removeLast() }
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
        didSet { if !Self.demo { UserDefaults.standard.set(try? JSONEncoder().encode(timer), forKey: "timerState") } }
    }
    var now = Date()
    @ObservationIgnored private var tick: Timer?

    init() {
        if Self.demo {
            wmjURL = "https://app11.workamajig.com"
            email = "sam.taylor@acme.example"
            defaultServiceCode = "CRTV"
            isConfigured = true
            // Pre-seeded running timer so screenshots show the live state
            // (WMJ_DEMO_IDLE=1 keeps it idle for start-form screenshots).
            if ProcessInfo.processInfo.environment["WMJ_DEMO_IDLE"] != "1" {
                timer.start(TaskSelection(projectNumber: "ACME-1042", projectName: "Website Redesign",
                                          taskID: "30", taskName: "Development", serviceCode: "DEV"),
                            at: Date().addingTimeInterval(-(47 * 60 + 23)))
            }
            syncTick()
            return
        }
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
        if Self.demo {
            services = Self.demoServices
            projects = Self.demoProjects.sorted { $0.projectName < $1.projectName }
            return
        }
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

    /// Tasks for a project — the one lookup views need on demand.
    func tasks(projectKey: String) async throws -> [WMJTask] {
        Self.demo ? Self.demoTasks : try await api.tasks(projectKey: projectKey)
    }

    /// Post time using the lowercased email as userID — Workamajig accepts it
    /// directly, and employees/search needs permissions not everyone has.
    func submitTime(selection: TaskSelection, hours: Double, workDate: Date = Date(),
                    comments: String = "") async throws {
        if Self.demo { return }
        // Merge-on-submit: a row already on that day for the same
        // project/task/service gets its hours bumped instead of a duplicate
        // row. If the lookup itself fails we fall back to posting a new row —
        // logging time must never be blocked by the read.
        if let existing = (try? await api.timeEntries(on: workDate))?.firstMatch(selection) {
            try await api.updateTime(timeKey: existing.timeKey, hours: existing.actualHours + hours)
            return
        }
        try await api.submit(TimeEntry(userID: email.lowercased(), hours: hours,
                                       projectNumber: selection.projectNumber,
                                       taskID: selection.taskID, serviceCode: selection.serviceCode,
                                       workDate: workDate, comments: comments))
    }

    func submitTimer() async throws {
        guard let selection = timer.selection else { return }
        try await submitTime(selection: selection, hours: timer.submittableHours())
        discardTimer()
    }

    /// Settings "Save & Verify": confirms the URL and tokens with a
    /// lightweight authenticated call (no employees/search — not every user
    /// has permission for it).
    func verifyConnection() async throws {
        if Self.demo { return }
        _ = try await api.services()
    }

    // MARK: Formatting

    func elapsedText(short: Bool) -> String {
        let seconds = Int(timer.elapsed(now: now))
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return short ? String(format: "%d:%02d", h, m) : String(format: "%d:%02d:%02d", h, m, s)
    }
}

// MARK: - Demo data (WMJ_DEMO=1) — fake but realistic, safe for public screenshots

extension AppModel {
    static let demoProjects = [
        Project(projectKey: "d1", projectNumber: "ACME-1042", projectName: "Website Redesign", clientName: "Acme Co."),
        Project(projectKey: "d2", projectNumber: "ACME-1055", projectName: "Spring Social Campaign", clientName: "Acme Co."),
        Project(projectKey: "d3", projectNumber: "NORTH-2201", projectName: "Brand Refresh", clientName: "Northwind Outfitters"),
        Project(projectKey: "d4", projectNumber: "GLOBEX-3310", projectName: "Q3 Media Plan", clientName: "Globex Corporation"),
        Project(projectKey: "d5", projectNumber: "INIT-4400", projectName: "Product Launch Video", clientName: "Initech"),
    ]
    static let demoTasks = [
        WMJTask(taskKey: "t1", taskID: "10", taskName: "Discovery"),
        WMJTask(taskKey: "t2", taskID: "20", taskName: "Design"),
        WMJTask(taskKey: "t3", taskID: "30", taskName: "Development"),
        WMJTask(taskKey: "t4", taskID: "40", taskName: "Client Review"),
        WMJTask(taskKey: "t5", taskID: "50", taskName: "Project Management"),
    ]
    static let demoServices = [
        Service(serviceCode: "CRTV", description: "Creative"),
        Service(serviceCode: "DEV", description: "Development"),
        Service(serviceCode: "STRAT", description: "Strategy"),
        Service(serviceCode: "AM", description: "Account Management"),
    ]
}
