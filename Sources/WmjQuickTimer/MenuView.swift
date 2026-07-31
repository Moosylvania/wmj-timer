import WmjQuickTimerCore
import SwiftUI

/// Menu bar dropdown: two actions that open their own panel window, plus the
/// usual Settings/Quit. All the real UI lives in the panels.
struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.isConfigured {
            Button(timerLabel) { open(WindowID.timer) }
            Button("Quick Log") { open(WindowID.quickLog) }
        } else {
            Button("Set Up Workamajig…") { showSettings() }
        }
        Divider()
        Button("Settings…") { showSettings() }
            .keyboardShortcut(",")
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var timerLabel: String {
        switch model.timer.phase {
        case .idle: "Add Timer"
        case .running: "Timer — \(model.elapsedText(short: true))"
        case .stopped: "Timer Paused — \(model.elapsedText(short: true))"
        }
    }

    /// Accessory apps open windows behind others unless activated first.
    private func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
