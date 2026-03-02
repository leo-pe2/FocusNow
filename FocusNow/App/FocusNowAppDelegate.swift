import AppKit

@MainActor
final class FocusNowAppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: AppCoordinator?
}

