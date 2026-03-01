import XCTest
@testable import FocusNow

final class SessionEngineTests: XCTestCase {
    @MainActor
    func testStartTransitionsToRunningWork() async throws {
        let engine = SessionEngine()

        await engine.start(config: .default)
        let snapshot = await engine.currentSnapshot()
        let phase = snapshot.phase
        let remainingSeconds = snapshot.remainingSeconds

        XCTAssertEqual(phase, .runningWork)
        XCTAssertGreaterThan(remainingSeconds, 0)
    }

    @MainActor
    func testLockedWorkCannotStopWithoutOverridePermission() async throws {
        let engine = SessionEngine()
        let lockedConfig = TimerConfigSnapshot(
            workSeconds: 1500,
            shortBreakSeconds: 300,
            longBreakSeconds: 900,
            roundsBeforeLongBreak: 4,
            maxFocusRounds: 0,
            lockedModeEnabled: true
        )

        await engine.start(config: lockedConfig)
        let summary = await engine.stop(reason: .manualStop, allowDuringLockedMode: false)

        XCTAssertNil(summary)
    }

    @MainActor
    func testPauseAndResumePreserveSessionState() async throws {
        let engine = SessionEngine()

        await engine.start(config: .default)
        let runningSnapshot = await engine.currentSnapshot()

        await engine.pause()
        let pausedSnapshot = await engine.currentSnapshot()
        XCTAssertEqual(pausedSnapshot.phase, .pausedWork)
        XCTAssertEqual(pausedSnapshot.remainingSeconds, runningSnapshot.remainingSeconds)

        await engine.resume()
        let resumedSnapshot = await engine.currentSnapshot()
        XCTAssertEqual(resumedSnapshot.phase, .runningWork)
        XCTAssertEqual(resumedSnapshot.remainingSeconds, runningSnapshot.remainingSeconds)
    }
}
