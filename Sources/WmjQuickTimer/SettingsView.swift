import WmjQuickTimerCore
import ServiceManagement
import SwiftUI

/// Standard macOS preferences window (Settings scene) — stays open while the
/// user copies tokens from elsewhere; nothing is lost on focus changes.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var url = ""
    @State private var email = ""
    @State private var companyToken = ""
    @State private var userToken = ""
    @State private var showCompanyToken = false
    @State private var showUserToken = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var status: (message: String, isError: Bool)?
    @State private var verifying = false
    @State private var updateStatus: (message: String, isError: Bool)?
    @State private var checkingForUpdate = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Workamajig URL")
                        TextField("", text: $url, prompt: Text("https://app11.workamajig.com"))
                    }
                    GridRow {
                        Text("Email address")
                        TextField("", text: $email, prompt: Text("you@yourcompany.com"))
                    }
                    GridRow {
                        Text("Company API Token")
                        secretField($companyToken, revealed: $showCompanyToken)
                    }
                    GridRow {
                        Text("User API Token")
                        secretField($userToken, revealed: $showUserToken)
                    }
                }
                .textFieldStyle(.roundedBorder)
            } footer: {
                Text("Tokens are stored in your macOS Keychain. Find your User API Token in Workamajig by clicking your name (top right).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { toggleLaunchAtLogin() }
            } footer: {
                Text("Menu bar icon hidden by the notch? Press ⌃⌥T (Timer) or ⌃⌥L (Quick Log) anywhere, or launch Wmj Quick Timer again from Spotlight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Save & Verify") { saveAndVerify() }
                        .buttonStyle(.borderedProminent)
                        .disabled(url.isEmpty || email.isEmpty || companyToken.isEmpty || userToken.isEmpty || verifying)
                    if verifying { ProgressView().controlSize(.small) }
                }
                if let status {
                    Text(status.message)
                        .font(.caption)
                        .foregroundStyle(status.isError ? .red : .green)
                }
            }

            Section {
                HStack {
                    Text("Version \(AppModel.currentVersion)")
                    Spacer()
                    if checkingForUpdate {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check for Updates") { checkForUpdates() }
                    }
                }
                if let updateStatus {
                    Text(updateStatus.message)
                        .font(.caption)
                        .foregroundStyle(updateStatus.isError ? .red : .secondary)
                }
                if model.availableUpdate != nil {
                    Button("Show Update…") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: WindowID.update)
                    }
                }
            } footer: {
                Text("Wmj Quick Timer checks GitHub for a new release twice a day while it's running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .regularWhileOpen()
        .onAppear {
            url = model.wmjURL
            email = model.email
            // Demo mode never touches the real Keychain (screenshots would show real tokens).
            let tokens = AppModel.demo
                ? Keychain.Tokens(company: "demo-company-api-token", user: "demo-user-api-token")
                : Keychain.tokens()
            companyToken = tokens?.company ?? ""
            userToken = tokens?.user ?? ""
        }
    }

    /// Masked by default with an eye toggle, so a mistyped token is checkable.
    private func secretField(_ text: Binding<String>, revealed: Binding<Bool>) -> some View {
        HStack(spacing: 4) {
            if revealed.wrappedValue {
                TextField("", text: text)
            } else {
                SecureField("", text: text)
            }
            Button {
                revealed.wrappedValue.toggle()
            } label: {
                Image(systemName: revealed.wrappedValue ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .help(revealed.wrappedValue ? "Hide token" : "Show token")
        }
    }

    private func saveAndVerify() {
        model.saveCredentials(url: url.trimmingCharacters(in: .whitespaces),
                              email: email.trimmingCharacters(in: .whitespaces),
                              companyToken: companyToken.trimmingCharacters(in: .whitespaces),
                              userToken: userToken.trimmingCharacters(in: .whitespaces))
        verifying = true
        status = nil
        Task {
            defer { verifying = false }
            do {
                try await model.verifyConnection()
                status = ("Connected", false)
            } catch {
                status = (error.localizedDescription, true)
            }
        }
    }

    private func checkForUpdates() {
        checkingForUpdate = true
        updateStatus = nil
        Task {
            defer { checkingForUpdate = false }
            await model.checkForUpdate(force: true)
            if let error = model.updateCheckError {
                updateStatus = (error, true)
            } else if let update = model.availableUpdate {
                updateStatus = ("Version \(update.version) is available.", false)
            } else if AppModel.currentVersion == "0.0.0" {
                // ponytail: `swift run` has no bundle version to compare against.
                updateStatus = ("Update checks only run from the installed app.", false)
            } else {
                updateStatus = ("You're up to date.", false)
            }
        }
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // ponytail: fails under `swift run` (no app bundle) — expected; works from the .app
            status = ("Launch at login unavailable: \(error.localizedDescription)", true)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
