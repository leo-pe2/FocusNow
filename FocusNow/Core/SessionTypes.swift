import Foundation

enum SessionPhase: String, Codable, CaseIterable, Sendable {
    case idle
    case runningWork
    case runningShortBreak
    case runningLongBreak
    case pausedWork
    case pausedShortBreak
    case pausedLongBreak
    case completed

    nonisolated var isWork: Bool {
        self == .runningWork || self == .pausedWork
    }

    nonisolated var isBreak: Bool {
        self == .runningShortBreak
            || self == .runningLongBreak
            || self == .pausedShortBreak
            || self == .pausedLongBreak
    }

    nonisolated var isPaused: Bool {
        self == .pausedWork
            || self == .pausedShortBreak
            || self == .pausedLongBreak
    }
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

    nonisolated var isRunning: Bool {
        phase == .runningWork || phase == .runningShortBreak || phase == .runningLongBreak
    }

    nonisolated var isPaused: Bool {
        phase.isPaused
    }

    nonisolated var isActive: Bool {
        isRunning || isPaused
    }
}

struct SessionSummary: Sendable {
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Int
    var completedPomodoros: Int
    var endedReason: SessionEndedReason
    var lockedOverrideUsed: Bool
}
