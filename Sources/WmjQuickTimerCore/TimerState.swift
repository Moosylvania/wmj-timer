import Foundation

/// What the timer (or a quick log) is charging time to.
public struct TaskSelection: Codable, Equatable, Sendable {
    public var projectNumber: String
    public var projectName: String
    public var taskID: String
    public var taskName: String
    public var serviceCode: String

    public init(projectNumber: String, projectName: String, taskID: String,
                taskName: String, serviceCode: String) {
        self.projectNumber = projectNumber
        self.projectName = projectName
        self.taskID = taskID
        self.taskName = taskName
        self.serviceCode = serviceCode
    }
}

public enum TimerPhase: Codable, Equatable, Sendable {
    case idle
    case running(startedAt: Date, accumulated: TimeInterval)
    case stopped(accumulated: TimeInterval)
}

/// Pure state machine; elapsed time always derives from wall-clock dates so it
/// survives sleep and app relaunch without drift.
public struct TimerState: Codable, Equatable, Sendable {
    public var phase: TimerPhase = .idle
    public var selection: TaskSelection?

    public init() {}

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    public func elapsed(now: Date = Date()) -> TimeInterval {
        switch phase {
        case .idle:
            return 0
        case .running(let startedAt, let accumulated):
            return accumulated + max(0, now.timeIntervalSince(startedAt))
        case .stopped(let accumulated):
            return accumulated
        }
    }

    /// Only one timer at a time: starting is only legal from idle.
    @discardableResult
    public mutating func start(_ selection: TaskSelection, at now: Date = Date()) -> Bool {
        guard case .idle = phase else { return false }
        self.selection = selection
        phase = .running(startedAt: now, accumulated: 0)
        return true
    }

    public mutating func stop(at now: Date = Date()) {
        if case .running = phase {
            phase = .stopped(accumulated: elapsed(now: now))
        }
    }

    public mutating func resume(at now: Date = Date()) {
        if case .stopped(let accumulated) = phase {
            phase = .running(startedAt: now, accumulated: accumulated)
        }
    }

    /// Swap what a running/stopped timer charges to, keeping the elapsed time —
    /// the recovery path when Workamajig rejects the original selection.
    public mutating func reassign(_ selection: TaskSelection) {
        if case .idle = phase { return }
        self.selection = selection
    }

    public mutating func discard() {
        phase = .idle
        selection = nil
    }

    /// Hours to submit for the current elapsed time, quarter-hour rounded.
    public func submittableHours(now: Date = Date()) -> Double {
        TimeMath.quarterHours(fromSeconds: elapsed(now: now))
    }
}
