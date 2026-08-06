import WmjQuickTimerCore
import SwiftUI

enum WindowID {
    static let timer = "timer"
    static let quickLog = "quickLog"
    static let update = "update"
    static let today = "today"
}

/// Update window: what's new, and a button that downloads, verifies and
/// installs the release without the user touching Finder.
struct UpdatePanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let release = model.availableUpdate {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(release.version) is available").font(.headline)
                    Text("You have \(AppModel.currentVersion).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    ScrollView {
                        // SwiftUI parses markdown from a LocalizedStringKey, so
                        // the CHANGELOG-derived notes render as-is.
                        Text(.init(notes))
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 240)
                }
                status(for: release)
            } else {
                Text("You're up to date").font(.headline)
                Text("Version \(AppModel.currentVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panelChrome()
    }

    @ViewBuilder
    private func status(for release: GitHubRelease) -> some View {
        switch model.updater.phase {
        case .revealed(let url):
            Text("Couldn't replace the installed app, so \(release.version) was saved to \(url.deletingLastPathComponent().lastPathComponent). Drag it into your Applications folder to finish.")
                .font(.caption)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        default:
            HStack {
                Button("Download & Install") { Task { await model.updater.install(release) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.updater.isBusy)
                if model.updater.isBusy {
                    ProgressView().controlSize(.small)
                    Text(busyLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Link("Release Notes", destination: release.htmlURL).font(.caption)
            }
            if case .failed(let message) = model.updater.phase {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            if model.updater.isBusy {
                Text("The app will quit and reopen once the update is installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var busyLabel: String {
        switch model.updater.phase {
        case .downloading: "Downloading…"
        case .verifying: "Verifying signature…"
        case .installing: "Installing…"
        default: ""
        }
    }
}

/// Timer window: start a timer, or control the one that's running.
struct TimerPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var submitting = false
    @State private var submitError: String?
    @State private var changingTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.timer.phase {
            case .idle:
                Text("Start a Timer").font(.headline)
                LogTimeForm(submitLabel: "Start", showsHours: false) { selection, _, _ in
                    // A failed check throws back into the form's error text and
                    // the timer never starts.
                    try await model.validateCanLog(selection)
                    model.startTimer(selection)
                    dismiss()
                }
            case .running:
                elapsedHeader
                Button { model.stopTimer() } label: {
                    Label("Stop", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case .stopped:
                elapsedHeader
                if changingTask {
                    // Re-point the timer without losing elapsed time — the way
                    // out when Workamajig rejects the original selection.
                    LogTimeForm(submitLabel: "Save", showsHours: false,
                                prefill: model.timer.selection) { selection, _, _ in
                        model.changeTaskSelection(selection)
                        submitError = nil
                        changingTask = false
                    }
                    Button("Cancel") { changingTask = false }
                } else {
                    Text("Will log \(model.timer.submittableHours(), format: .number) hours")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Resume") { model.resumeTimer() }
                        Button("Submit Time") { submit() }
                            .buttonStyle(.borderedProminent)
                            .disabled(submitting)
                        Spacer()
                        Button("Discard", role: .destructive) {
                            model.discardTimer()
                            dismiss()
                        }
                    }
                    Button("Change Project…") { changingTask = true }
                        .buttonStyle(.link)
                        .font(.caption)
                    if submitting { ProgressView().controlSize(.small) }
                }
            }
            if let message = submitError ?? model.loadError {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .panelChrome()
        .task { await model.refresh() }
    }

    private var elapsedHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.elapsedText(short: false))
                .font(.system(size: 34, weight: .medium).monospacedDigit())
            if let selection = model.timer.selection {
                Text("\(selection.projectName) · \(selection.taskName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func submit() {
        submitting = true
        submitError = nil
        Task {
            defer { submitting = false }
            do {
                try await model.submitTimer()
                dismiss()
            } catch {
                submitError = error.localizedDescription
            }
        }
    }
}

/// Quick Log window: project/task/service + hours, straight to today's timesheet.
struct QuickLogPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Log").font(.headline)
            LogTimeForm(submitLabel: "Log Time", showsHours: true) { selection, hours, date in
                try await model.submitTime(selection: selection, hours: hours, workDate: date)
            }
            if let message = model.loadError {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .panelChrome()
        .task { await model.refresh() }
    }
}

/// Today panel: what's already on today's timesheet, resolved to names, with a
/// link out to the full Workamajig timesheet.
struct TodayPanel: View {
    @Environment(AppModel.self) private var model
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Today's Time").font(.headline)
                if loading {
                    ProgressView().controlSize(.mini)
                    Text("Syncing…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.todayRows.isEmpty && !loading {
                Text("No time logged today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !loading {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Project")
                        Text("Task")
                        Text("Service")
                        Text("Hours").gridColumnAlignment(.trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(model.todayRows) { row in
                        GridRow {
                            Text(row.projectName)
                            Text(row.taskName)
                            Text(row.serviceName)
                            Text(row.hours, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
            if let url = URL(string: model.wmjURL), !model.wmjURL.isEmpty {
                Link("View Full Timesheet", destination: url)
            }
            if let message = model.loadError {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .panelChrome(width: 520)
        .task {
            // Reset explicitly: the window is hidden, not destroyed, on close,
            // so @State survives and `loading` is false on every reopen.
            loading = true
            // refresh first: the name joins need projects/services loaded.
            await model.refresh()
            await model.loadToday()
            loading = false
        }
        // Panel left open past midnight: refetch for the new day.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task {
                loading = true
                await model.loadToday()
                loading = false
            }
        }
    }
}

/// Drops the containing window under the menu bar icon instead of wherever
/// SwiftUI last left it.
private struct StatusItemAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Next runloop: the window exists and has been sized to its content.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // ponytail: the status item's own window is the only handle SwiftUI
            // gives us to its position.
            let anchor = NSApp.windows.first { $0.className.contains("StatusBarWindow") }?.frame
            let screen = NSScreen.screens.first { $0.frame.contains(anchor?.origin ?? .zero) }
                ?? NSScreen.main ?? NSScreen.screens[0]
            let visible = screen.visibleFrame
            let target = anchor ?? CGRect(x: visible.maxX, y: visible.maxY, width: 0, height: 0)
            let x = min(max(visible.minX + 8, target.midX - window.frame.width / 2),
                        visible.maxX - window.frame.width - 8)
            window.setFrameTopLeftPoint(CGPoint(x: x, y: min(target.minY - 4, visible.maxY)))
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func panelChrome(width: CGFloat = 380) -> some View {
        padding(16)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(StatusItemAnchor())
            .regularWhileOpen()
    }

    /// While one of our windows is open the app behaves like a regular app
    /// (Dock icon, ⌘-Tab, stays visible when another app is focused), then
    /// drops back to menu-bar-only on close.
    func regularWhileOpen() -> some View {
        onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.async {
                    for window in NSApp.windows where window.styleMask.contains(.titled) {
                        window.hidesOnDeactivate = false
                    }
                }
            }
            .onDisappear {
                // Other panels may still be open — only the last one flips back.
                DispatchQueue.main.async {
                    let open = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
                    if !open { NSApp.setActivationPolicy(.accessory) }
                }
            }
    }
}
