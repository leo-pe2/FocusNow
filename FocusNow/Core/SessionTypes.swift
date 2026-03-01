import Foundation

enum SessionPhase: String, Codable, CaseIterable, Sendable {
    case idle
    case runningWork
    case runningShortBreak
    case runningLongBreak
    case completed

    nonisolated var isWork: Bool { self == .runningWork }
    nonisolated var isBreak: Bool { self == .runningShortBreak || self == .runningLongBreak }
}

struct SessionSnapshot: Sendable {
    var phase: SessionPhase
    var remainingSeconds: Int
    var currentRound: Int
    var completedPomodoros: Int
    var roundsBeforeLongBreak: Int
    var maxFocusRounds: Int
    var isLockedModeEnabled: Bool
    var startedAt: Date?

    nonisolated static let idle = SessionSnapshot(
        phase: .idle,
        remainingSeconds: 0,
        currentRound: 0,
        completedPomodoros: 0,
        roundsBeforeLongBreak: 4,
        maxFocusRounds: 0,
        isLockedModeEnabled: false,
        startedAt: nil
    )

    nonisolated var isRunning: Bool { phase == .runningWork || phase.isBreak }
}

struct SessionSummary: Sendable {
    var startedAt: Date
    var endedAt: Date
    var completedPomodoros: Int
    var endedReason: SessionEndedReason
    var lockedOverrideUsed: Bool

    var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}
