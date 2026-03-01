import AppKit
import SwiftUI

struct MainPopoverView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.openSettings) private var openSettings

    @State private var lockedStopPIN: String = ""
    @State private var isHoveringSettingsButton = false
    @State private var isHoveringQuitButton = false
    @State private var isHoveringProfileButton = false
    @State private var isHoveringStartStopButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(coordinator.timerString)
                .font(.system(size: 42, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)

            primaryControlsRow

            if coordinator.sessionSnapshot.phase.isBreak {
                Button("Skip Break") {
                    Task {
                        await coordinatorSkipBreak()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let roundsLeftLabel = coordinator.roundsLeftLabel {
                Text(roundsLeftLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            lockedStopSection
            scheduleSection

            Divider()

            actionButtonsRow
        }
        .padding(12)
        .frame(width: 320)
        .alert("FocusNow", isPresented: Binding(get: {
            coordinator.lastErrorMessage != nil
        }, set: { presented in
            if !presented {
                coordinator.clearError()
            }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.lastErrorMessage ?? "")
        }
        .onAppear {
            coordinator.ensureProfileAvailability()
        }
    }

    private var primaryControlsRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(coordinator.availableProfiles) { profile in
                    Button(profile.name) {
                        coordinator.makeProfileActive(profile)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(coordinator.activeProfile?.name ?? "Select Profile")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHoveringProfileButton ? Color.accentColor.opacity(0.16) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isHoveringProfileButton ? Color.accentColor : Color.primary)
            .onHover { hovering in
                isHoveringProfileButton = hovering
            }

            Button {
                coordinator.toggleSession()
            } label: {
                Text(coordinator.sessionSnapshot.isRunning ? "Stop" : "Start")
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isHoveringStartStopButton ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isHoveringStartStopButton ? Color.accentColor : Color.primary)
            .onHover { hovering in
                isHoveringStartStopButton = hovering
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next Schedule")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let nextScheduleDate = coordinator.nextScheduleDate {
                Text(nextScheduleDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
            } else {
                Text("No active schedule")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 8) {
            Button {
                openSettingsWindow()
            } label: {
                Label("Open Settings…", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isHoveringSettingsButton ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHoveringSettingsButton ? Color.accentColor : Color.primary)
            .onHover { hovering in
                isHoveringSettingsButton = hovering
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isHoveringQuitButton ? Color.red.opacity(0.14) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHoveringQuitButton ? Color.red : Color.primary)
            .onHover { hovering in
                isHoveringQuitButton = hovering
            }
        }
    }

    private var lockedStopSection: some View {
        Group {
            if coordinator.requiresLockedPinPrompt {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Locked mode is active. Enter your PIN to stop this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        SecureField("PIN", text: $lockedStopPIN)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                submitLockedStopPIN()
                            }

                        Button("Unlock") {
                            submitLockedStopPIN()
                        }
                        .disabled(lockedStopPIN.isEmpty)

                        Button("Cancel") {
                            lockedStopPIN = ""
                            coordinator.cancelLockedStopPrompt()
                        }
                    }
                }
            }
        }
    }

    private func coordinatorSkipBreak() async {
        await coordinator.skipBreak()
    }

    private func submitLockedStopPIN() {
        coordinator.stopSessionWithPIN(lockedStopPIN)
        lockedStopPIN = ""
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            if let settingsWindow = NSApp.windows.first(where: { window in
                (window.identifier?.rawValue == "com.apple.SwiftUI.Settings")
                    || window.title.localizedCaseInsensitiveContains("settings")
            }) {
                settingsWindow.makeKeyAndOrderFront(nil)
                settingsWindow.orderFrontRegardless()
            }
        }
    }
}
