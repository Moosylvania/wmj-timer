import WmjQuickTimerCore
import SwiftUI

enum WindowID {
    static let timer = "timer"
    static let quickLog = "quickLog"
}

/// Timer window: start a timer, or control the one that's running.
struct TimerPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var submitting = false
    @State private var submitError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.timer.phase {
            case .idle:
                Text("Start a Timer").font(.headline)
                LogTimeForm(submitLabel: "Start", showsHours: false) { selection, _, _ in
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
                if submitting { ProgressView().controlSize(.small) }
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
    func panelChrome() -> some View {
        padding(16)
            .frame(width: 380)
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
