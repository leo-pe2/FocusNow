import AppKit
import Combine
import Foundation
import SwiftData

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var sessionSnapshot: SessionSnapshot = .idle
    @Published private(set) var blockerStatus: BlockerStatus = .inactive
    @Published private(set) var activeProfile: Profile?
    @Published private(set) var availableProfiles: [Profile] = []
    @Published private(set) var idleConfiguredWorkSeconds: Int = 25 * 60
    @Published private(set) var idleConfiguredMaxFocusRounds: Int = 0
    @Published private(set) var nextScheduleDate: Date?
    @Published var requiresLockedPinPrompt = false
    @Published var lastErrorMessage: String?

    let modelContext: ModelContext

    private let profileManager: ProfileManager
    private let scheduleManager = ScheduleManager()
    private let sessionEngine = SessionEngine()
    private let statsManager: StatsManager
    private let blockingCoordinator: BlockingCoordinator
    private let notificationManager: NotificationManager
    private let keychainPINStore = KeychainPINStore()
    private let launchAtLoginManager = LaunchAtLoginManager()

    private var updateTask: Task<Void, Never>?
    private var settings: AppSettings?
    private var notificationObservers: [(NotificationCenter, NSObjectProtocol)] = []

    init(modelContext: ModelContext, notificationManager: NotificationManager) {
        self.modelContext = modelContext
        self.notificationManager = notificationManager
        self.profileManager = ProfileManager(modelContext: modelContext)
        self.statsManager = StatsManager(modelContext: modelContext)

        let websiteBlocker = SystemWebsiteBlockerAdapter()
        let appBlocker = SystemAppBlocker(notificationManager: notificationManager)
        self.blockingCoordinator = BlockingCoordinator(websiteBlocker: websiteBlocker, appBlocker: appBlocker)

        notificationManager.prepareAuthorizationIfNeeded()
        bootstrap()
        subscribeToSessionUpdates()
        registerSystemObservers()
    }

    deinit {
        updateTask?.cancel()
        for (center, token) in notificationObservers {
            center.removeObserver(token)
        }
    }

    var sessionLabel: String {
        switch sessionSnapshot.phase {
        case .idle:
            return "Idle"
        case .runningWork:
            return "Focus"
        case .runningShortBreak:
            return "Short Break"
        case .runningLongBreak:
            return "Long Break"
        case .pausedWork:
            return "Paused Focus"
        case .pausedShortBreak, .pausedLongBreak:
            return "Paused Break"
        case .completed:
            return "Completed"
        }
    }

    var timerString: String {
        let total = sessionSnapshot.isActive
            ? max(0, sessionSnapshot.remainingSeconds)
            : max(0, idleConfiguredWorkSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var statusSymbolName: String {
        switch blockerStatus {
        case .degraded:
            return "exclamationmark.triangle.fill"
        case .active:
            return sessionSnapshot.phase.isBreak ? "cup.and.saucer.fill" : "flame.fill"
        case .inactive:
            switch sessionSnapshot.phase {
            case .runningWork:
                return "flame.fill"
            case .runningShortBreak, .runningLongBreak:
                return "cup.and.saucer.fill"
            case .pausedWork:
                return "pause.circle.fill"
            case .pausedShortBreak, .pausedLongBreak:
                return "pause.circle"
            case .idle, .completed:
                return "circle.grid.2x2"
            }
        }
    }

    var roundsLeftExponentText: String {
        let maxRounds = effectiveMaxFocusRounds
        guard maxRounds > 0 else { return "∞" }

        let remaining = max(0, maxRounds - sessionSnapshot.completedPomodoros)
        return "\(remaining)"
    }

    var roundsLeftHelpText: String {
        let maxRounds = effectiveMaxFocusRounds
        guard maxRounds > 0 else {
            return "Rounds left: infinite. Auto-stop after rounds is turned off."
        }

        return "Rounds left until auto-stop. The session ends after \(maxRounds) completed focus rounds."
    }

    func startSession(profileName: String?, manualWorkSeconds: Int?) {
        if let profileName {
            switchProfile(named: profileName)
        }

        guard let profile = activeProfile else { return }
        do {
            let timerConfig = try profileManager.timerConfig(for: profile.id)
            let snapshot = TimerConfigSnapshot(
                workSeconds: timerConfig.workSeconds,
                shortBreakSeconds: timerConfig.shortBreakSeconds,
                longBreakSeconds: timerConfig.longBreakSeconds,
                roundsBeforeLongBreak: timerConfig.roundsBeforeLongBreak,
                maxFocusRounds: max(0, timerConfig.maxFocusRounds ?? 0),
                lockedModeEnabled: timerConfig.lockedModeEnabled
            )

            Task {
                await sessionEngine.start(config: snapshot, manualWorkSeconds: manualWorkSeconds)
            }
        } catch {
            lastErrorMessage = "Could not load timer settings."
        }
    }

    func toggleSession() {
        if sessionSnapshot.isActive {
            stopSessionIfAllowed()
        } else {
            startSession(profileName: nil, manualWorkSeconds: nil)
        }
    }

    func pauseSession() {
        guard sessionSnapshot.isRunning else { return }

        Task {
            await sessionEngine.pause()
        }
    }

    func resumeSession() {
        guard sessionSnapshot.isPaused else { return }

        Task {
            await sessionEngine.resume()
        }
    }

    func stopSessionIfAllowed() {
        if sessionSnapshot.phase.isWork,
           sessionSnapshot.isLockedModeEnabled,
           hasPINConfigured {
            requiresLockedPinPrompt = true
            return
        }

        stopSession(reason: .manualStop, allowDuringLockedMode: true)
    }

    func stopSessionWithPIN(_ pin: String) {
        guard let key = settings?.lockedPinReferenceKey else {
            lastErrorMessage = "PIN is not configured."
            return
        }

        guard keychainPINStore.verifyPIN(pin, key: key) else {
            lastErrorMessage = "Invalid PIN."
            return
        }

        requiresLockedPinPrompt = false
        stopSession(reason: .lockedOverride, allowDuringLockedMode: true)
    }

    func cancelLockedStopPrompt() {
        requiresLockedPinPrompt = false
    }

    func skipBreak() async {
        await sessionEngine.skipBreak()
    }

    func switchProfile(named name: String) {
        do {
            let profiles = try profileManager.fetchProfiles()
            availableProfiles = profiles

            guard let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                lastErrorMessage = "Profile '\(name)' not found."
                return
            }

            if activeProfile?.id == profile.id {
                return
            }

            activeProfile = profile
            settings?.activeProfileID = profile.id
            try modelContext.save()

            refreshIdleTimerDisplay()
            refreshSchedules()
        } catch {
            lastErrorMessage = "Could not switch profile."
        }
    }

    func makeProfileActive(_ profile: Profile) {
        if activeProfile?.id == profile.id {
            return
        }

        activeProfile = profile
        if !availableProfiles.contains(where: { $0.id == profile.id }) {
            availableProfiles.append(profile)
            availableProfiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        settings?.activeProfileID = profile.id
        try? modelContext.save()
        refreshIdleTimerDisplay()
        refreshSchedules()
    }

    func reloadProfiles() {
        ensureProfileAvailability()
    }

    func reloadIdleTimerDisplay() {
        refreshIdleTimerDisplay()
    }

    func savePIN(_ pin: String) {
        guard let key = settings?.lockedPinReferenceKey else {
            lastErrorMessage = "PIN key is missing."
            return
        }

        do {
            try keychainPINStore.setPIN(pin, key: key)
        } catch {
            lastErrorMessage = "Unable to store PIN."
        }
    }

    var hasPINConfigured: Bool {
        guard let key = settings?.lockedPinReferenceKey else { return false }
        return keychainPINStore.hasPIN(key: key)
    }

    func setLaunchAtLogin(enabled: Bool) {
        settings?.launchAtLoginEnabled = enabled
        do {
            try launchAtLoginManager.setEnabled(enabled)
            try modelContext.save()
        } catch {
            lastErrorMessage = "Unable to update launch at login."
            settings?.launchAtLoginEnabled = !enabled
        }
    }

    func sessionTotalsForCurrentMonth() -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let from = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let to = calendar.date(byAdding: .month, value: 1, to: from)
        else {
            return 0
        }

        return statsManager.totalFocusSeconds(from: from, to: to)
    }

    func streakCount() -> Int {
        statsManager.streakCount()
    }

    func appSettings() -> AppSettings? {
        settings
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func ensureProfileAvailability() {
        do {
            let profiles = try profileManager.fetchProfiles()
            availableProfiles = profiles

            if profiles.isEmpty {
                let created = try profileManager.bootstrapDefaultsIfNeeded()
                settings = try loadOrCreateSettings(defaultProfileID: created.id)
                activeProfile = created
                availableProfiles = [created]
                refreshIdleTimerDisplay()
                refreshSchedules()
                return
            }

            let activeProfileID = activeProfile?.id
            let matchingActiveProfile = activeProfileID.flatMap { id in
                profiles.first(where: { $0.id == id })
            }

            if let matchingActiveProfile {
                activeProfile = matchingActiveProfile
                refreshIdleTimerDisplay()
                return
            }

            activeProfile = try profileManager.activeProfile(settings: settings) ?? profiles.first
            if let active = activeProfile {
                settings?.activeProfileID = active.id
                try? modelContext.save()
            }
            refreshIdleTimerDisplay()
            refreshSchedules()
        } catch {
            lastErrorMessage = "Profile setup failed."
        }
    }

    func reloadSchedules() {
        refreshSchedules()
    }

    private func bootstrap() {
        do {
            let profile = try profileManager.bootstrapDefaultsIfNeeded()
            settings = try loadOrCreateSettings(defaultProfileID: profile.id)
            let profiles = try profileManager.fetchProfiles()
            availableProfiles = profiles
            activeProfile = try profileManager.activeProfile(settings: settings) ?? profiles.first ?? profile
            if let active = activeProfile {
                settings?.activeProfileID = active.id
                try? modelContext.save()
            }
            refreshIdleTimerDisplay()
            refreshSchedules()

            if settings?.launchAtLoginEnabled == true {
                try? launchAtLoginManager.setEnabled(true)
            }
        } catch {
            lastErrorMessage = "Bootstrap failed."
        }
    }

    private func subscribeToSessionUpdates() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }

            var previousSnapshot: SessionSnapshot = .idle
            for await latest in self.sessionEngine.updates {
                await MainActor.run {
                    self.sessionSnapshot = latest
                    self.handleTransition(from: previousSnapshot, to: latest)
                    self.blockerStatus = self.blockingCoordinator.combinedStatus()
                    previousSnapshot = latest
                }
            }
        }
    }

    private func handleTransition(from old: SessionSnapshot, to new: SessionSnapshot) {
        guard let profile = activeProfile else { return }

        if old.phase != new.phase {
            if old.phase == .runningWork,
               new.phase.isBreak,
               new.maxFocusRounds > 0,
               new.completedPomodoros >= new.maxFocusRounds {
                stopSession(reason: .completed, allowDuringLockedMode: true)
                return
            }

            if old.phase == .runningWork {
                switch new.phase {
                case .runningShortBreak:
                    notificationManager.send(
                        title: "Short Break Started",
                        body: "Focus round complete. Time for a short break."
                    )
                case .runningLongBreak:
                    notificationManager.send(
                        title: "Long Break Started",
                        body: "Cycle complete. Time for a long break."
                    )
                default:
                    break
                }
            }

            if new.phase == .runningWork {
                applyBlocking(for: profile)
            } else if new.phase.isPaused || new.phase.isBreak || new.phase == .idle || new.phase == .completed {
                blockingCoordinator.disableAll()
                blockerStatus = blockingCoordinator.combinedStatus()
            }

        }
    }

    private func applyBlocking(for profile: Profile) {
        do {
            let websiteRules = try profileManager.websiteRules(for: profile.id).filter(\.isEnabled)
            let appRules = try profileManager.appRules(for: profile.id).filter(\.isEnabled)

            // The UI is blocklist-only. Treat all enabled website rules as block rules
            // so stale allowlist records do not disable website blocking.
            let websiteProfile = WebsiteBlockingProfile(mode: .blocklist, patterns: websiteRules.map(\.pattern))
            let appProfile = AppBlockingProfile(blockedBundleIdentifiers: Set(appRules.map(\.bundleIdentifier)))
            blockingCoordinator.applyForWork(websiteProfile: websiteProfile, appProfile: appProfile)
            blockerStatus = blockingCoordinator.combinedStatus()
        } catch {
            blockerStatus = .degraded("Blocking setup failed")
        }
    }

    private func stopSession(reason: SessionEndedReason, allowDuringLockedMode: Bool) {
        Task {
            guard let summary = await sessionEngine.stop(reason: reason, allowDuringLockedMode: allowDuringLockedMode) else {
                await MainActor.run {
                    self.lastErrorMessage = "Locked mode prevents ending this session."
                }
                return
            }

            await MainActor.run {
                if let profileID = self.activeProfile?.id {
                    self.statsManager.recordSession(summary: summary, profileID: profileID)
                }
                self.blockingCoordinator.disableAll()
                self.blockerStatus = self.blockingCoordinator.combinedStatus()
            }
        }
    }

    private func loadOrCreateSettings(defaultProfileID: UUID) throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try modelContext.fetch(descriptor).first {
            if existing.activeProfileID == nil {
                existing.activeProfileID = defaultProfileID
                try modelContext.save()
            }
            return existing
        }

        let settings = AppSettings(activeProfileID: defaultProfileID)
        modelContext.insert(settings)
        try modelContext.save()
        return settings
    }

    private func refreshSchedules() {
        guard let activeProfile else { return }
        let rules = (try? profileManager.scheduleRules(for: activeProfile.id)) ?? []

        scheduleManager.arm(rules: rules) { [weak self] in
            guard let self else { return }
            self.startSession(profileName: nil, manualWorkSeconds: nil)
            self.refreshSchedules()
        }

        nextScheduleDate = scheduleManager.nextTriggerDate
    }

    private func refreshIdleTimerDisplay() {
        guard let activeProfile else {
            idleConfiguredWorkSeconds = 25 * 60
            idleConfiguredMaxFocusRounds = 0
            return
        }

        let config = try? profileManager.timerConfig(for: activeProfile.id)
        idleConfiguredWorkSeconds = max(1, config?.workSeconds ?? 25 * 60)
        idleConfiguredMaxFocusRounds = max(0, config?.maxFocusRounds ?? 0)
    }

    private var effectiveMaxFocusRounds: Int {
        if sessionSnapshot.isActive {
            return max(0, sessionSnapshot.maxFocusRounds)
        }

        return max(0, idleConfiguredMaxFocusRounds)
    }

    private func registerSystemObservers() {
        let dayToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSchedules()
            }
        }
        notificationObservers.append((NotificationCenter.default, dayToken))

        let timezoneToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSchedules()
            }
        }
        notificationObservers.append((NotificationCenter.default, timezoneToken))

        let wakeCenter = NSWorkspace.shared.notificationCenter
        let wakeToken = wakeCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSchedules()
            }
        }
        notificationObservers.append((wakeCenter, wakeToken))
    }
}
