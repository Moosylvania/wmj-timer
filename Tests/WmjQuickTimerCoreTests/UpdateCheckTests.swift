import XCTest
@testable import WmjQuickTimerCore

final class UpdateCheckTests: XCTestCase {
    func testIsNewerComparesNumerically() {
        XCTAssertTrue(UpdateCheck.isNewer("0.3.0", than: "0.2.2"))
        XCTAssertTrue(UpdateCheck.isNewer("0.2.10", than: "0.2.2"))   // not a string compare
        XCTAssertTrue(UpdateCheck.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertFalse(UpdateCheck.isNewer("0.2.2", than: "0.2.2"))
        XCTAssertFalse(UpdateCheck.isNewer("0.2.1", than: "0.2.2"))
    }

    func testIsNewerToleratesTagPrefixAndShortVersions() {
        XCTAssertTrue(UpdateCheck.isNewer("v0.3.0", than: "0.2.2"))
        XCTAssertTrue(UpdateCheck.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.0", than: "1.0.0"))
        // `swift run` has no bundle version; the sentinel must look ancient.
        XCTAssertTrue(UpdateCheck.isNewer("0.2.2", than: "0.0.0"))
    }

    /// Trimmed from the live `releases/latest` response for Moosylvania/wmj-timer.
    func testDecodesLatestReleasePayload() throws {
        let json = """
        {
          "tag_name": "v0.2.2",
          "name": "0.2.2",
          "draft": false,
          "prerelease": false,
          "html_url": "https://github.com/Moosylvania/wmj-timer/releases/tag/v0.2.2",
          "body": "\\n### Fixed\\n\\n- Task lists no longer fail.",
          "assets": [
            {
              "name": "Wmj-Quick-Timer-0.2.2.zip",
              "content_type": "application/zip",
              "size": 664789,
              "browser_download_url": "https://github.com/Moosylvania/wmj-timer/releases/download/v0.2.2/Wmj-Quick-Timer-0.2.2.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v0.2.2")
        XCTAssertEqual(release.version, "0.2.2")
        XCTAssertEqual(release.body, "\n### Fixed\n\n- Task lists no longer fail.")
        XCTAssertEqual(release.zipAsset?.name, "Wmj-Quick-Timer-0.2.2.zip")
        XCTAssertEqual(release.zipAsset?.size, 664789)
        XCTAssertEqual(release.zipAsset?.browserDownloadURL.lastPathComponent, "Wmj-Quick-Timer-0.2.2.zip")
    }

    func testReleaseWithoutZipHasNoAsset() throws {
        let json = """
        {"tag_name": "v9.9.9", "html_url": "https://example.com", "body": null,
         "assets": [{"name": "notes.txt", "size": 1,
                     "browser_download_url": "https://example.com/notes.txt"}]}
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(GitHubRelease.self, from: json).zipAsset)
    }
}
