import Foundation
import Observation
import UserNotifications
import WmjQuickTimerCore

@Observable @MainActor
final class AppModel {
    /// `WMJ_DEMO=1` runs the UI on canned data for screenshots: no API calls,
    /// no Keychain reads, no UserDefaults writes. See AGENTS.md.
    static let demo = ProcessInfo.processInfo.environment["WMJ_DEMO"] == "1"

    /// Only the packaged .app has a version — `swift run` gets the sentinel,
    /// which suppresses update checks entirely (see `checkForUpdate`).
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

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
    /// This user's Workamajig userKey, bootstrapped from their own timesheet
    /// (see `APIClient.recentActivity`) — drives the assigned-task filter.
    var userKey: String? = UserDefaults.standard.string(forKey: "userKey") {
        didSet { if !Self.demo { UserDefaults.standard.set(userKey, forKey: "userKey") } }
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
    var todayRows: [TodayRow] = []
    /// Calendar day `todayRows` was last fetched on, so day rollover can invalidate it.
    @ObservationIgnored private var todayFetched: Date?
    var loadError: String?
    /// Projects on the user's recent timesheets, most recent first — used only
    /// to rank the search list (membership can't be queried; see AGENTS.md).
    @ObservationIgnored private var recentProjectKeys: [String] = []
    @ObservationIgnored private var loading = false

    // MARK: Timer

    var timer = TimerState() {
        didSet { if !Self.demo { UserDefaults.standard.set(try? JSONEncoder().encode(timer), forKey: "timerState") } }
    }
    var now = Date()
    @ObservationIgnored private var tick: Timer?

    // MARK: Updates

    /// Set when GitHub's latest release is newer than this build — drives the
    /// menu item and the update panel.
    var availableUpdate: GitHubRelease?
    /// Only surfaced for manual checks; a flaky network shouldn't nag.
    var updateCheckError: String?
    let updater = Updater()
    @ObservationIgnored private var updatePoll: Timer?
    @ObservationIgnored private var checkingForUpdate = false

    private var lastUpdateCheck: Date? {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck") }
    }

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
            if ProcessInfo.processInfo.environment["WMJ_DEMO_UPDATE"] == "1" {
                availableUpdate = Self.demoRelease
            }
            return
        }
        isConfigured = !wmjURL.isEmpty && !email.isEmpty
            && Keychain.tokens() != nil
        if let data = UserDefaults.standard.data(forKey: "timerState"),
           let saved = try? JSONDecoder().decode(TimerState.self, from: data) {
            timer = saved
        }
        syncTick()
        startUpdatePolling()
    }

    func startTimer(_ selection: TaskSelection) {
        timer.start(selection)
        syncTick()
    }

    /// Pre-start proof that the user can log time to the selection — the only
    /// authoritative check the API offers is a real POST. A row already on
    /// today's timesheet for the same project/task/service is proof by itself;
    /// otherwise post a 0-hour entry and leave it (optimistic: stop/submit
    /// merges the real hours into that row). Throws to block the timer.
    func validateCanLog(_ selection: TaskSelection) async throws {
        if Self.demo { return }
        if let existing = try? await api.timeEntries(on: Date()),
           existing.firstMatch(selection) != nil { return }
        do {
            try await api.submit(TimeEntry(userID: email.lowercased(), hours: 0,
                                           projectNumber: selection.projectNumber,
                                           taskID: selection.taskID,
                                           serviceCode: selection.serviceCode,
                                           workDate: Date(),
                                           // The API requires a comment on 0-hour entries.
                                           comments: "WMJ Quick Timer"))
        } catch let error as URLError {
            // Offline must never block a local timer; submit surfaces it later.
            APIClient.log("pre-start validation skipped (network): \(error)")
        }
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

    /// Re-point a running/stopped timer at a different project/task/service,
    /// keeping the elapsed time — for when Workamajig rejects the original.
    func changeTaskSelection(_ selection: TaskSelection) {
        timer.reassign(selection)
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

    // MARK: Updates

    /// Checks at launch and hourly thereafter. The hourly tick plus the 12h
    /// guard in `checkForUpdate` is what makes this survive sleep/wake — a bare
    /// 12h timer silently skips a day when the Mac sleeps through it.
    private func startUpdatePolling() {
        Task { await checkForUpdate() }
        updatePoll = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in await self.checkForUpdate() }
        }
    }

    /// `force` skips the twice-daily throttle and surfaces errors — that's the
    /// Settings "Check Now" path.
    func checkForUpdate(force: Bool = false) async {
        guard !Self.demo, Self.currentVersion != "0.0.0", !checkingForUpdate else { return }
        if !force, let last = lastUpdateCheck, Date().timeIntervalSince(last) < 12 * 3600 { return }
        checkingForUpdate = true
        defer { checkingForUpdate = false }
        do {
            let release = try await UpdateCheck.fetchLatest()
            lastUpdateCheck = Date()
            updateCheckError = nil
            guard UpdateCheck.isNewer(release.tagName, than: Self.currentVersion) else {
                availableUpdate = nil
                return
            }
            availableUpdate = release
            notifyOnce(about: release)
        } catch {
            // Silent unless the user asked: an offline laptop must not nag.
            updateCheckError = force ? error.localizedDescription : nil
        }
    }

    /// One banner per version, so a machine left running for a week doesn't get
    /// a notification every hour about the same release.
    private func notifyOnce(about release: GitHubRelease) {
        guard Bundle.main.bundleIdentifier != nil,   // UNUserNotificationCenter traps unbundled
              UserDefaults.standard.string(forKey: "notifiedVersion") != release.version else { return }
        UserDefaults.standard.set(release.version, forKey: "notifiedVersion")
        let version = release.version
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Wmj Quick Timer \(version) is available"
            content.body = "You have \(Self.currentVersion). Choose “Update…” from the menu bar to install it."
            try? await center.add(UNNotificationRequest(identifier: "update-\(version)",
                                                        content: content, trigger: nil))
        }
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
            if recentProjectKeys.isEmpty {
                // Once per session: my userKey + recently-logged projects, from
                // my own timesheet. Optional data — a failure must not block
                // the project list (but does get logged).
                do {
                    let recent = try await api.recentActivity()
                    if let key = recent.userKey { userKey = key }
                    recentProjectKeys = recent.projectKeys
                } catch {
                    APIClient.log("recentActivity failed: \(error)")
                }
            }
            let rank = Dictionary(uniqueKeysWithValues:
                recentProjectKeys.enumerated().map { ($1, $0) })
            projects = try await api.projects().sorted {
                (rank[$0.projectKey] ?? .max, $0.projectName) < (rank[$1.projectKey] ?? .max, $1.projectName)
            }
            loadError = nil
        } catch is CancellationError {
            // View went away mid-fetch — not something to show the user.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Today's timesheet entries resolved to names for the Today panel.
    /// Needs `refresh()` to have populated projects/services first.
    func loadToday() async {
        if Self.demo {
            todayRows = TodayRow.build(entries: Self.demoTodayEntries, projects: Self.demoProjects,
                                       services: Self.demoServices, tasksByProject: ["d1": Self.demoTasks])
            return
        }
        guard isConfigured else { return }
        // Rows fetched on a previous calendar day aren't "today" anymore —
        // drop them so the panel shows a loading state instead of stale data.
        if let fetched = todayFetched, !Calendar.current.isDateInToday(fetched) {
            todayRows = []
        }
        do {
            let entries = try await api.timeEntries(on: Date())
            var tasksByProject: [String: [WMJTask]] = [:]
            // A day's timesheet has single-digit distinct projects — far under
            // the ~55-request 429 ceiling. A failed lookup just shows raw taskIDs.
            for key in Set(entries.compactMap(\.projectKey)) {
                tasksByProject[key] = (try? await api.tasks(projectKey: key)) ?? []
            }
            todayRows = TodayRow.build(entries: entries, projects: projects,
                                       services: services, tasksByProject: tasksByProject)
            todayFetched = Date()
            loadError = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Tasks for a project the user can plausibly log time to: not completed,
    /// and assigned to them or unassigned. The API has no real "can log time"
    /// check short of POSTing an entry, so this is the best available gate.
    func tasks(projectKey: String) async throws -> [WMJTask] {
        let all = Self.demo ? Self.demoTasks : try await api.tasks(projectKey: projectKey)
        return all.filter { $0.isActive && $0.isAvailable(to: Self.demo ? "me" : userKey) }
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
    /// Includes a completed task and one assigned to someone else, so demo mode
    /// exercises the filter in `tasks(projectKey:)` — three tasks show.
    static let demoTasks = [
        WMJTask(taskKey: "t1", taskID: "10", taskName: "Discovery",
                percComp: 100, completedByDate: "6/2/2026 12:00:00 AM"),
        WMJTask(taskKey: "t2", taskID: "20", taskName: "Design",
                taskUsers: [TaskUser(userKey: "someone-else")]),
        WMJTask(taskKey: "t3", taskID: "30", taskName: "Development",
                taskUsers: [TaskUser(userKey: "me")]),
        WMJTask(taskKey: "t4", taskID: "40", taskName: "Client Review"),
        WMJTask(taskKey: "t5", taskID: "50", taskName: "Project Management"),
    ]
    /// `WMJ_DEMO_UPDATE=1` — a pending release for update-panel screenshots.
    static let demoRelease = GitHubRelease(
        tagName: "v0.3.0",
        body: """
            ### Added

            - Automatic update checks, twice a day, with one-click install.

            ### Fixed

            - The Quick Log date resets to today each time the window opens.
            """,
        htmlURL: URL(string: "https://github.com/Moosylvania/wmj-timer/releases/tag/v0.3.0")!,
        assets: [.init(name: "Wmj-Quick-Timer-0.3.0.zip",
                       browserDownloadURL: URL(string: "https://example.invalid/demo.zip")!,
                       size: 664_789)])

    /// Today panel rows: two resolve against `demoTasks`, one exercises the
    /// raw-taskID fallback (nil projectKey), and the 0-hour row must be hidden.
    static let demoTodayEntries = [
        TimesheetEntry(timeKey: "e1", actualHours: 1.5, projectNumber: "ACME-1042",
                       taskID: "30", serviceCode: "dev", workDate: "2026-08-05T00:00:00", projectKey: "d1"),
        TimesheetEntry(timeKey: "e2", actualHours: 0.75, projectNumber: "ACME-1042",
                       taskID: "50", serviceCode: "crtv", workDate: "2026-08-05T00:00:00", projectKey: "d1"),
        TimesheetEntry(timeKey: "e3", actualHours: 2, projectNumber: "NORTH-2201",
                       taskID: "2.1.1", serviceCode: "strat", workDate: "2026-08-05T00:00:00"),
        TimesheetEntry(timeKey: "e4", actualHours: 0, projectNumber: "GLOBEX-3310",
                       taskID: "10", serviceCode: "am", workDate: "2026-08-05T00:00:00", projectKey: "d4"),
    ]

    static let demoServices = [
        Service(serviceCode: "CRTV", description: "Creative"),
        Service(serviceCode: "DEV", description: "Development"),
        Service(serviceCode: "STRAT", description: "Strategy"),
        Service(serviceCode: "AM", description: "Account Management"),
    ]
}
