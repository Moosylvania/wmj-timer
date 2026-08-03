import Foundation

/// A GitHub release, decoded from `/releases/latest`. Only the fields the
/// updater needs — GitHub sends about eighty.
public struct GitHubRelease: Decodable, Sendable, Equatable {
    public var tagName: String
    /// Release notes. `scripts/release.sh` fills this from the CHANGELOG section.
    public var body: String?
    public var htmlURL: URL
    public var assets: [Asset]

    public struct Asset: Decodable, Sendable, Equatable {
        public var name: String
        public var browserDownloadURL: URL
        public var size: Int

        public init(name: String, browserDownloadURL: URL, size: Int) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
            self.size = size
        }

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    public init(tagName: String, body: String?, htmlURL: URL, assets: [Asset]) {
        self.tagName = tagName
        self.body = body
        self.htmlURL = htmlURL
        self.assets = assets
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case assets
    }

    /// Tag without the `v` prefix — what the bundle's version string looks like.
    public var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// The distributed app zip. `package.sh` only ever attaches one.
    public var zipAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }
}

public enum UpdateCheck {
    public static let latestURL = URL(string: "https://api.github.com/repos/Moosylvania/wmj-timer/releases/latest")!

    /// Compares dotted numeric versions, tolerating a `v` prefix and differing
    /// component counts ("1.0" < "1.0.1"). Non-numeric junk reads as 0.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let (x, y) = (i < a.count ? a[i] : 0, i < b.count ? b[i] : 0)
            if x != y { return x > y }
        }
        return false
    }

    static func components(_ version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return trimmed.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    public static func fetchLatest(session: URLSession = .shared) async throws -> GitHubRelease {
        var request = URLRequest(url: latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.checkFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

public enum UpdateError: LocalizedError, Equatable {
    case checkFailed(Int)
    case noDownload
    case unpackFailed(String)
    case untrusted
    case versionMismatch(expected: String, got: String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .checkFailed(let status):
            "Couldn't reach GitHub to check for updates (\(status))."
        case .noDownload:
            "That release has no downloadable app."
        case .unpackFailed(let detail):
            "Couldn't unpack the update: \(detail)"
        case .untrusted:
            "The downloaded update isn't signed by Moosylvania — it was not installed."
        case .versionMismatch(let expected, let got):
            "The downloaded app is version \(got), not \(expected) — it was not installed."
        case .installFailed(let detail):
            "Couldn't install the update: \(detail)"
        }
    }
}
