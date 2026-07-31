import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, even when run via `swift run` without the bundle plist.
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct WmjQuickTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var model = AppModel()


    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(model)
        } label: {
            // Icon always shows, so a bare running clock is still identifiable.
            MenuBarLabel(model: model)
        }

        Window("Timer", id: WindowID.timer) {
            TimerPanel()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Window("Quick Log", id: WindowID.quickLog) {
            QuickLogPanel()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Status item label. Also the demo hook: it's the one view alive at launch,
/// so `WMJ_DEMO_OPEN=timer|quicklog|settings` can open a window for
/// screenshots without UI scripting.
private struct MenuBarLabel: View {
    let model: AppModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// Bundled chess-clock glyph; nil under `swift run` (no bundle Resources).
    private static let menuBarIcon: NSImage? = {
        guard let icon = NSImage(named: "MenuBarIcon") else { return nil }
        icon.isTemplate = true   // follows menu bar light/dark and highlight
        return icon
    }()

    var body: some View {
        Label {
            if model.timer.isRunning {
                Text(model.elapsedText(short: false)).monospacedDigit()
            }
        } icon: {
            if let icon = Self.menuBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "timer")
            }
        }
        .labelStyle(.titleAndIcon)
        .task {
            guard AppModel.demo else { return }
            NSApp.activate(ignoringOtherApps: true)
            switch ProcessInfo.processInfo.environment["WMJ_DEMO_OPEN"] {
            case "timer": openWindow(id: WindowID.timer)
            case "quicklog": openWindow(id: WindowID.quickLog)
            case "settings": openSettings()
            default: break
            }
        }
    }
}
