import AppKit
import Foundation

@MainActor
final class SystemAppBlocker: AppBlocker {
    private static let notificationCooldown: TimeInterval = 30

    private let notificationManager: NotificationManager
    private let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

    private var launchObserver: NSObjectProtocol?
    private var reconcileTask: Task<Void, Never>?
    private var terminationTasks: [pid_t: Task<Void, Never>] = [:]
    private var lastNotificationDateByBundleIdentifier: [String: Date] = [:]
    private var blockedBundleIdentifiers: Set<String> = []
    private var currentStatus: BlockerStatus = .inactive

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    deinit {
        if let launchObserver {
            workspaceNotificationCenter.removeObserver(launchObserver)
        }
        reconcileTask?.cancel()
        terminationTasks.values.forEach { $0.cancel() }
    }

    func enable(profile: AppBlockingProfile) {
        blockedBundleIdentifiers = profile.blockedBundleIdentifiers
        currentStatus = blockedBundleIdentifiers.isEmpty ? .inactive : .active

        guard !blockedBundleIdentifiers.isEmpty else {
            stopObservers()
            return
        }

        startObserversIfNeeded()
        terminateBlockedRunningAppsIfNeeded()
    }

    func disable() {
        blockedBundleIdentifiers = []
        lastNotificationDateByBundleIdentifier.removeAll()
        currentStatus = .inactive
        stopObservers()
    }

    func status() -> BlockerStatus {
        currentStatus
    }

    private func startObserversIfNeeded() {
        if launchObserver == nil {
            launchObserver = workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                guard
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    let bundleIdentifier = app.bundleIdentifier
                else {
                    return
                }

                Task { @MainActor [weak self] in
                    self?.terminateIfBlocked(app: app, bundleIdentifier: bundleIdentifier)
                }
            }
        }

        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    self.terminateBlockedRunningAppsIfNeeded()
                }
            }
        }
    }

    private func stopObservers() {
        if let launchObserver {
            workspaceNotificationCenter.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        reconcileTask?.cancel()
        reconcileTask = nil
        terminationTasks.values.forEach { $0.cancel() }
        terminationTasks.removeAll()
    }

    private func terminateBlockedRunningAppsIfNeeded() {
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            terminateIfBlocked(app: app, bundleIdentifier: bundleIdentifier)
        }
    }

    private func terminateIfBlocked(app: NSRunningApplication, bundleIdentifier: String) {
        guard blockedBundleIdentifiers.contains(bundleIdentifier) else { return }
        guard bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        guard app.activationPolicy == .regular else { return }
        let processIdentifier = app.processIdentifier
        guard processIdentifier > 0 else { return }
        guard terminationTasks[processIdentifier] == nil else { return }

        terminationTasks[processIdentifier] = Task { @MainActor [weak self] in
            await self?.attemptTermination(
                app: app,
                bundleIdentifier: bundleIdentifier,
                processIdentifier: processIdentifier
            )
        }
    }

    private func attemptTermination(
        app: NSRunningApplication,
        bundleIdentifier: String,
        processIdentifier: pid_t
    ) async {
        defer {
            terminationTasks[processIdentifier] = nil
        }

        guard blockedBundleIdentifiers.contains(bundleIdentifier) else { return }

        if !app.isTerminated {
            _ = app.terminate()
            try? await Task.sleep(for: .milliseconds(600))
        }

        if !app.isTerminated {
            _ = app.forceTerminate()
            try? await Task.sleep(for: .milliseconds(600))
        }

        guard app.isTerminated else { return }
        sendBlockedNotificationIfNeeded(
            bundleIdentifier: bundleIdentifier,
            appName: app.localizedName ?? bundleIdentifier
        )
    }

    private func sendBlockedNotificationIfNeeded(bundleIdentifier: String, appName: String) {
        let now = Date()
        if let lastNotificationDate = lastNotificationDateByBundleIdentifier[bundleIdentifier],
           now.timeIntervalSince(lastNotificationDate) < Self.notificationCooldown {
            return
        }

        lastNotificationDateByBundleIdentifier[bundleIdentifier] = now
        notificationManager.send(
            title: "FocusNow",
            body: "\(appName) was blocked during focus time."
        )
    }
}
