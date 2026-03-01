import Foundation

@MainActor
protocol AppBlocker: AnyObject {
    func enable(profile: AppBlockingProfile)
    func disable()
    func status() -> BlockerStatus
}
