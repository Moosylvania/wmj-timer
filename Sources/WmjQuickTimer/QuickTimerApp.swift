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

    /// Bundled chess-clock glyph; nil under `swift run` (no bundle Resources).
    private static let menuBarIcon: NSImage? = {
        guard let icon = NSImage(named: "MenuBarIcon") else { return nil }
        icon.isTemplate = true   // follows menu bar light/dark and highlight
        return icon
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(model)
        } label: {
            // Icon always shows, so a bare running clock is still identifiable.
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
