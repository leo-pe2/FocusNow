import SwiftData
import SwiftUI

@main
struct FocusNowApp: App {
    @NSApplicationDelegateAdaptor(FocusNowAppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    @StateObject private var coordinator: AppCoordinator

    init() {
        let modelContainer = FocusNowModelContainer.make()
        self.modelContainer = modelContainer

        let context = modelContainer.mainContext
        let notificationManager = NotificationManager()
        _coordinator = StateObject(wrappedValue: AppCoordinator(modelContext: context, notificationManager: notificationManager))
    }

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
                .environmentObject(coordinator)
                .onAppear {
                    appDelegate.coordinator = coordinator
                }
        } label: {
            if coordinator.sessionSnapshot.isActive {
                Text(coordinator.timerString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            } else {
                Image("timer")
            }
        }
        .menuBarExtraStyle(.window)
        .modelContainer(modelContainer)

        Window("Settings", id: "settings") {
            SettingsRootView()
                .environmentObject(coordinator)
                .onAppear {
                    appDelegate.coordinator = coordinator
                }
        }
        .defaultSize(width: 760, height: 520)
        .windowResizability(.contentMinSize)
        .modelContainer(modelContainer)
    }
}
