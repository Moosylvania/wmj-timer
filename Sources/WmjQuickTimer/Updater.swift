import AppKit
import Observation
import WmjQuickTimerCore

/// Downloads a GitHub release zip, checks it really is our signed app, and
/// swaps it in over the running bundle.
///
/// Zips fetched with URLSession carry no `com.apple.quarantine` xattr, so the
/// installed copy doesn't trip Gatekeeper on first launch the way a
/// browser-downloaded one would.
@Observable @MainActor
final class Updater {
    enum Phase: Equatable {
        case idle
        case downloading
        case verifying
        case installing
        /// Couldn't write next to the running app — the new one is in Downloads.
        case revealed(URL)
        case failed(String)
    }

    /// The signature the downloaded app must satisfy: our Developer ID team and
    /// our bundle id, chained to Apple. Anything else is not installed.
    /// The leading `=` is required — without it codesign reads the argument as
    /// a path to a requirement file and fails every check, genuine or not.
    private static let requirement = """
        =anchor apple generic \
        and certificate leaf[subject.OU] = "RTNF9A97B6" \
        and identifier "com.moosylvania.QuickTimer"
        """

    private(set) var phase: Phase = .idle

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying, .installing: true
        default: false
        }
    }

    func install(_ release: GitHubRelease) async {
        do {
            guard let asset = release.zipAsset else { throw UpdateError.noDownload }

            phase = .downloading
            let staging = try stagingDirectory()
            defer { try? FileManager.default.removeItem(at: staging) }
            let zip = staging.appending(path: asset.name)
            try await download(asset.browserDownloadURL, to: zip)

            phase = .verifying
            let unpacked = staging.appending(path: "unpacked")
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path],
                   onFailure: UpdateError.unpackFailed)
            let newApp = try appBundle(in: unpacked)
            try verify(newApp, expecting: release.version)

            phase = .installing
            let destination = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
                phase = .revealed(try moveToDownloads(newApp))
                return
            }
            try swapAndRelaunch(from: newApp, to: destination)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Steps

    private func stagingDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "WmjQuickTimerUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func download(_ remote: URL, to local: URL) async throws {
        // ponytail: no progress bar — the zip is under a megabyte. Switch to
        // URLSession.bytes(for:) with a byte count if it ever gets big.
        let (temp, response) = try await URLSession.shared.download(from: remote)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.checkFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try FileManager.default.moveItem(at: temp, to: local)
    }

    private func appBundle(in directory: URL) throws -> URL {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                    includingPropertiesForKeys: nil)) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.unpackFailed("no .app in the archive")
        }
        return app
    }

    /// The trust boundary: an unsigned, ad-hoc-signed, or third-party-signed
    /// bundle never gets installed, and neither does one whose version doesn't
    /// match the release we thought we were downloading.
    private func verify(_ app: URL, expecting version: String) throws {
        do {
            try run("/usr/bin/codesign",
                   ["--verify", "--strict", "-R", Self.requirement, app.path],
                   onFailure: UpdateError.unpackFailed)
        } catch {
            throw UpdateError.untrusted
        }
        let found = Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        guard found == version else {
            throw UpdateError.versionMismatch(expected: version, got: found)
        }
    }

    private func moveToDownloads(_ app: URL) throws -> URL {
        let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let destination = downloads.appending(path: app.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try run("/usr/bin/ditto", [app.path, destination.path], onFailure: UpdateError.installFailed)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        return destination
    }

    /// A running bundle can't reliably replace itself, so hand the swap to a
    /// detached shell that waits for us to exit, then relaunches the new copy.
    ///
    /// ponytail: no rollback if `open` fails after the move — the old bundle is
    /// already gone by then. A real login-item helper is the upgrade path if
    /// that ever bites.
    private func swapAndRelaunch(from source: URL, to destination: URL) throws {
        let staged = destination.deletingLastPathComponent()
            .appending(path: destination.lastPathComponent + ".new")
        // Copy out of the temp dir first: `defer` deletes it the moment we return.
        try? FileManager.default.removeItem(at: staged)
        try run("/usr/bin/ditto", [source.path, staged.path], onFailure: UpdateError.installFailed)

        let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            rm -rf \(quote(destination.path)) \
            && mv \(quote(staged.path)) \(quote(destination.path)) \
            && open \(quote(destination.path))
            """
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", script]
        do {
            try sh.run()   // deliberately not waited on — it outlives us
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw UpdateError.installFailed(error.localizedDescription)
        }
        NSApp.terminate(nil)
    }

    // MARK: Shell helpers

    private func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func run(_ tool: String, _ arguments: [String],
                     onFailure: (String) -> UpdateError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw onFailure(detail.isEmpty ? "\(tool) exited \(process.terminationStatus)" : detail)
        }
    }
}
