import AppKit
import Foundation

@MainActor
final class SystemAppBlocker: AppBlocker {
    private let notificationManager: NotificationManager

    private var launchObserver: NSObjectProtocol?
    private var reconcileTask: Task<Void, Never>?
    private var blockedBundleIdentifiers: Set<String> = []
    private var currentStatus: BlockerStatus = .inactive

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    deinit {
        if let launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
        }
        reconcileTask?.cancel()
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
        currentStatus = .inactive
        stopObservers()
    }

    func status() -> BlockerStatus {
        currentStatus
    }

    private func startObserversIfNeeded() {
        if launchObserver == nil {
            launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
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
            NotificationCenter.default.removeObserver(launchObserver)
            self.launchObserver = nil
        }
        reconcileTask?.cancel()
        reconcileTask = nil
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

        _ = app.terminate()

        notificationManager.send(
            title: "FocusNow",
            body: "\(app.localizedName ?? bundleIdentifier) was blocked during focus time."
        )
    }
}
