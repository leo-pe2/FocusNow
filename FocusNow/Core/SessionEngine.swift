import Foundation

actor SessionEngine {
    private var snapshot: SessionSnapshot = .idle
    private var timerConfig: TimerConfigSnapshot = .default
    private var sessionStartDate: Date?
    private var lockedOverrideUsed = false

    private var updateContinuation: AsyncStream<SessionSnapshot>.Continuation?
    nonisolated let updates: AsyncStream<SessionSnapshot>

    private var tickerTask: Task<Void, Never>?

    init() {
        var continuation: AsyncStream<SessionSnapshot>.Continuation?
        updates = AsyncStream { streamContinuation in
            continuation = streamContinuation
        }
        updateContinuation = continuation
        continuation?.yield(snapshot)
    }

    deinit {
        tickerTask?.cancel()
        updateContinuation?.finish()
    }

    func currentSnapshot() -> SessionSnapshot {
        snapshot
    }

    func start(config: TimerConfigSnapshot, manualWorkSeconds: Int? = nil) {
        if snapshot.isRunning {
            return
        }

        timerConfig = config
        let workSeconds = max(1, manualWorkSeconds ?? config.workSeconds)
        sessionStartDate = Date()
        lockedOverrideUsed = false

        snapshot = SessionSnapshot(
            phase: .runningWork,
            remainingSeconds: workSeconds,
            currentRound: 1,
            completedPomodoros: 0,
            roundsBeforeLongBreak: max(1, config.roundsBeforeLongBreak),
            maxFocusRounds: max(0, config.maxFocusRounds),
            isLockedModeEnabled: config.lockedModeEnabled,
            startedAt: sessionStartDate
        )

        emit()
        startTickerIfNeeded()
    }

    func stop(reason: SessionEndedReason, allowDuringLockedMode: Bool) -> SessionSummary? {
        guard snapshot.phase != .idle else { return nil }
        guard let startedAt = sessionStartDate else { return nil }

        if snapshot.phase == .runningWork && snapshot.isLockedModeEnabled && !allowDuringLockedMode {
            return nil
        }

        if reason == .lockedOverride {
            lockedOverrideUsed = true
        }

        let summary = SessionSummary(
            startedAt: startedAt,
            endedAt: .now,
            completedPomodoros: snapshot.completedPomodoros,
            endedReason: reason,
            lockedOverrideUsed: lockedOverrideUsed
        )

        tickerTask?.cancel()
        tickerTask = nil

        snapshot.phase = .completed
        snapshot.remainingSeconds = 0
        emit()

        snapshot = .idle
        sessionStartDate = nil
        lockedOverrideUsed = false
        emit()

        return summary
    }

    func skipBreak() {
        guard snapshot.phase.isBreak else { return }
        snapshot.phase = .runningWork
        snapshot.remainingSeconds = timerConfig.workSeconds
        snapshot.currentRound += 1
        emit()
    }

    private func startTickerIfNeeded() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self.tick()
            }
        }
    }

    private func tick() {
        guard snapshot.isRunning else { return }
        guard snapshot.remainingSeconds > 0 else {
            transitionAfterZero()
            return
        }

        snapshot.remainingSeconds -= 1
        emit()

        if snapshot.remainingSeconds == 0 {
            transitionAfterZero()
        }
    }

    private func transitionAfterZero() {
        switch snapshot.phase {
        case .runningWork:
            snapshot.completedPomodoros += 1

            let roundsBeforeLongBreak = max(1, timerConfig.roundsBeforeLongBreak)
            let shouldTakeLongBreak = snapshot.completedPomodoros % roundsBeforeLongBreak == 0

            snapshot.phase = shouldTakeLongBreak ? .runningLongBreak : .runningShortBreak
            snapshot.remainingSeconds = shouldTakeLongBreak ? timerConfig.longBreakSeconds : timerConfig.shortBreakSeconds

        case .runningShortBreak, .runningLongBreak:
            snapshot.phase = .runningWork
            snapshot.currentRound += 1
            snapshot.remainingSeconds = timerConfig.workSeconds

        case .idle, .completed:
            return
        }

        emit()
    }

    private func emit() {
        updateContinuation?.yield(snapshot)
    }
}
