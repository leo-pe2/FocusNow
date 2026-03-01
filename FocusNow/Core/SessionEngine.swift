import Foundation

actor SessionEngine {
    private var snapshot: SessionSnapshot = .idle
    private var timerConfig: TimerConfigSnapshot = .default
    private var sessionStartDate: Date?
    private var lockedOverrideUsed = false
    private var pausedStartedAt: Date?
    private var accumulatedPausedSeconds = 0

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
        if snapshot.isActive || snapshot.phase == .completed {
            return
        }

        timerConfig = config
        let workSeconds = max(1, manualWorkSeconds ?? config.workSeconds)
        sessionStartDate = Date()
        lockedOverrideUsed = false
        pausedStartedAt = nil
        accumulatedPausedSeconds = 0

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

    func pause() {
        guard snapshot.isRunning else { return }

        tickerTask?.cancel()
        tickerTask = nil
        pausedStartedAt = Date()
        snapshot.phase = pausedPhase(for: snapshot.phase)
        emit()
    }

    func resume() {
        guard snapshot.isPaused else { return }

        accumulateCurrentPauseIfNeeded()
        snapshot.phase = runningPhase(for: snapshot.phase)
        emit()
        startTickerIfNeeded()
    }

    func stop(reason: SessionEndedReason, allowDuringLockedMode: Bool) -> SessionSummary? {
        guard snapshot.phase != .idle else { return nil }
        guard let startedAt = sessionStartDate else { return nil }

        if snapshot.phase.isWork && snapshot.isLockedModeEnabled && !allowDuringLockedMode {
            return nil
        }

        if reason == .lockedOverride {
            lockedOverrideUsed = true
        }

        let endedAt = Date()
        let activeDurationSeconds = max(
            0,
            Int(endedAt.timeIntervalSince(startedAt)) - accumulatedPausedSeconds - currentPauseSeconds()
        )

        let summary = SessionSummary(
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: activeDurationSeconds,
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
        pausedStartedAt = nil
        accumulatedPausedSeconds = 0
        emit()

        return summary
    }

    func skipBreak() {
        guard snapshot.phase.isBreak else { return }
        accumulateCurrentPauseIfNeeded()
        snapshot.phase = .runningWork
        snapshot.remainingSeconds = timerConfig.workSeconds
        snapshot.currentRound += 1
        emit()
        startTickerIfNeeded()
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

        case .idle, .completed, .pausedWork, .pausedShortBreak, .pausedLongBreak:
            return
        }

        emit()
    }

    private func pausedPhase(for phase: SessionPhase) -> SessionPhase {
        switch phase {
        case .runningWork:
            return .pausedWork
        case .runningShortBreak:
            return .pausedShortBreak
        case .runningLongBreak:
            return .pausedLongBreak
        default:
            return phase
        }
    }

    private func runningPhase(for phase: SessionPhase) -> SessionPhase {
        switch phase {
        case .pausedWork:
            return .runningWork
        case .pausedShortBreak:
            return .runningShortBreak
        case .pausedLongBreak:
            return .runningLongBreak
        default:
            return phase
        }
    }

    private func currentPauseSeconds() -> Int {
        guard let pausedStartedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(pausedStartedAt)))
    }

    private func accumulateCurrentPauseIfNeeded() {
        guard let pausedStartedAt else { return }
        accumulatedPausedSeconds += max(0, Int(Date().timeIntervalSince(pausedStartedAt)))
        self.pausedStartedAt = nil
    }

    private func emit() {
        updateContinuation?.yield(snapshot)
    }
}
