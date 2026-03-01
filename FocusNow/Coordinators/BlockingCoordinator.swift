import Foundation

@MainActor
final class BlockingCoordinator {
    private let websiteBlocker: WebsiteBlocker
    private let appBlocker: AppBlocker

    init(websiteBlocker: WebsiteBlocker, appBlocker: AppBlocker) {
        self.websiteBlocker = websiteBlocker
        self.appBlocker = appBlocker
    }

    func applyForWork(websiteProfile: WebsiteBlockingProfile, appProfile: AppBlockingProfile) {
        websiteBlocker.enable(profile: websiteProfile)
        appBlocker.enable(profile: appProfile)
    }

    func disableAll() {
        websiteBlocker.disable()
        appBlocker.disable()
    }

    func combinedStatus() -> BlockerStatus {
        let websiteStatus = websiteBlocker.status()
        let appStatus = appBlocker.status()

        switch (websiteStatus, appStatus) {
        case (.degraded(let reason), _):
            return .degraded(reason)
        case (_, .degraded(let reason)):
            return .degraded(reason)
        case (.active, _), (_, .active):
            return .active
        default:
            return .inactive
        }
    }
}
