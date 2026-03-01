import Foundation

enum BlockerStatus: Equatable, Sendable {
    case inactive
    case active
    case degraded(String)
}

@MainActor
protocol WebsiteBlocker: AnyObject {
    func enable(profile: WebsiteBlockingProfile)
    func disable()
    func status() -> BlockerStatus
}
