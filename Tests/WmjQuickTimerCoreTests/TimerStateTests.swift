import XCTest
@testable import WmjQuickTimerCore

final class TimerStateTests: XCTestCase {
    let selection = TaskSelection(projectNumber: "25-X-1", projectName: "X",
                                  taskID: "1", taskName: "Dev", serviceCode: "dev")
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testFullLifecycle() {
        var state = TimerState()
        XCTAssertEqual(state.elapsed(now: t0), 0)

        XCTAssertTrue(state.start(selection, at: t0))
        XCTAssertTrue(state.isRunning)
        XCTAssertFalse(state.start(selection, at: t0), "only one timer at a time")
        XCTAssertEqual(state.elapsed(now: t0.addingTimeInterval(600)), 600)

        state.stop(at: t0.addingTimeInterval(600))
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.elapsed(now: t0.addingTimeInterval(9999)), 600, "stopped time is frozen")

        state.resume(at: t0.addingTimeInterval(1000))
        XCTAssertEqual(state.elapsed(now: t0.addingTimeInterval(1300)), 900, "resume keeps accumulated")
        XCTAssertEqual(state.submittableHours(now: t0.addingTimeInterval(1300)), 0.25)

        state.discard()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.selection)
    }

    func testInvalidTransitionsAreNoOps() {
        var state = TimerState()
        state.stop()
        state.resume()
        XCTAssertEqual(state.phase, .idle)
    }

    func testCodableRoundTripWhileRunning() throws {
        var state = TimerState()
        state.start(selection, at: t0)
        state.stop(at: t0.addingTimeInterval(300))
        state.resume(at: t0.addingTimeInterval(400))

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(TimerState.self, from: data)
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.elapsed(now: t0.addingTimeInterval(700)), 600)
    }
}
