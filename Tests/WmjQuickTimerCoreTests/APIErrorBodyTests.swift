import XCTest
@testable import WmjQuickTimerCore

final class APIErrorBodyTests: XCTestCase {
    func testNestedErrorsShape() throws {
        // Verbatim POST /time 400 body.
        let json = Data("""
        {"event":"","logid":"708c8083-cf9e-4544-bf3f-407a3ca4276a","errors":[{"error":[{"message":"The project is valid, but the user doesn't have access to it.","status":400}]}]}
        """.utf8)
        let body = try JSONDecoder().decode(APIErrorBody.self, from: json)
        XCTAssertEqual(body.message, "The project is valid, but the user doesn't have access to it.")
    }

    func testMultipleNestedMessagesJoin() throws {
        let json = Data("""
        {"errors":[{"error":[{"message":"QueryString parameter searchFor is required"}]},{"error":[{"message":"QueryString parameter searchField is required"}]}]}
        """.utf8)
        let body = try JSONDecoder().decode(APIErrorBody.self, from: json)
        XCTAssertEqual(body.message,
                       "QueryString parameter searchFor is required QueryString parameter searchField is required")
    }

    func testLegacyDescriptionShape() throws {
        let json = Data(#"{"status":403,"description":"API access is not enabled"}"#.utf8)
        let body = try JSONDecoder().decode(APIErrorBody.self, from: json)
        XCTAssertEqual(body.message, "API access is not enabled")
    }

    func testBareStringErrors() throws {
        let json = Data(#"{"event":"","logid":"x","errors":["-3"]}"#.utf8)
        let body = try JSONDecoder().decode(APIErrorBody.self, from: json)
        XCTAssertEqual(body.message, "-3")
    }
}
