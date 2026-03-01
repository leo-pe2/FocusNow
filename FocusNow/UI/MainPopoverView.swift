import AppKit
import SwiftUI

struct MainPopoverView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    @State private var lockedStopPIN: String = ""
    @State private var isHoveringSettingsButton = false
    @State private var isHoveringQuitButton = false
    @State private var isHoveringProfileButton = false
    @State private var isHoveringStartButton = false
    @State private var isHoveringPauseButton = false
    @State private var isHoveringStopButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(coordinator.timerString)
                .font(.system(size: 42, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)
                .overlay(alignment: .topTrailing) {
                    Text(superscriptDigits(coordinator.roundsLeftExponentText))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .offset(x: -40, y: 10)
                        .help(coordinator.roundsLeftHelpText)
                }

            primaryControlsRow

            if coordinator.sessionSnapshot.phase.isBreak {
                Button("Skip Break") {
                    Task {
                        await coordinatorSkipBreak()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pointingHandCursor()
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
            if coordinator.sessionSnapshot.isActive {
                controlButton(
                    title: coordinator.sessionSnapshot.isPaused ? "Resume" : "Pause",
                    hover: $isHoveringPauseButton,
                    tint: .accentColor
                ) {
                    if coordinator.sessionSnapshot.isPaused {
                        coordinator.resumeSession()
                    } else {
                        coordinator.pauseSession()
                    }
                }

                controlButton(
                    title: "Stop",
                    hover: $isHoveringStopButton,
                    tint: .red
                ) {
                    coordinator.stopSessionIfAllowed()
                }
            } else {
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
                .pointingHandCursor()

                controlButton(
                    title: "Start",
                    hover: $isHoveringStartButton,
                    tint: .accentColor,
                    shortcut: .defaultAction
                ) {
                    coordinator.startSession(profileName: nil, manualWorkSeconds: nil)
                }
            }
        }
    }

    private var scheduleSection: some View {
        HStack(spacing: 8) {
            Text("Next Schedule:")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if let nextScheduleDate = coordinator.nextScheduleDate {
                    Text(nextScheduleDate.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("No active schedule")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 8) {
            Button {
                openSettingsWindow()
            } label: {
                Label("Open Settings", systemImage: "arrow.up.forward.app")
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
            .pointingHandCursor()

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
            .pointingHandCursor()
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
                        .pointingHandCursor()

                        Button("Cancel") {
                            lockedStopPIN = ""
                            coordinator.cancelLockedStopPrompt()
                        }
                        .pointingHandCursor()
                    }
                }
            }
        }
    }

    private func coordinatorSkipBreak() async {
        await coordinator.skipBreak()
    }

    private func controlButton(
        title: String,
        hover: Binding<Bool>,
        tint: Color,
        shortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hover.wrappedValue ? tint.opacity(0.16) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .foregroundStyle(hover.wrappedValue ? tint : Color.primary)
        .onHover { hovering in
            hover.wrappedValue = hovering
        }
        .pointingHandCursor()
        .modifier(OptionalKeyboardShortcut(shortcut: shortcut))
    }

    private func submitLockedStopPIN() {
        coordinator.stopSessionWithPIN(lockedStopPIN)
        lockedStopPIN = ""
    }

    private func superscriptDigits(_ text: String) -> String {
        let mapping: [Character: Character] = [
            "0": "⁰",
            "1": "¹",
            "2": "²",
            "3": "³",
            "4": "⁴",
            "5": "⁵",
            "6": "⁶",
            "7": "⁷",
            "8": "⁸",
            "9": "⁹"
        ]

        return String(text.map { mapping[$0] ?? $0 })
    }

    private func openSettingsWindow() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        locateAndConfigureSettingsWindow()
    }

    private func locateAndConfigureSettingsWindow(retryCount: Int = 8) {
        if let settingsWindow = NSApp.windows.first(where: { window in
            (window.identifier?.rawValue == "settings")
                || (window.identifier?.rawValue == "com.apple.SwiftUI.settings")
                || (window.identifier?.rawValue == "com.apple.SwiftUI.Settings")
                || window.title.localizedCaseInsensitiveContains("settings")
        }) {
            configureSettingsWindow(settingsWindow)
            return
        }

        guard retryCount > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            locateAndConfigureSettingsWindow(retryCount: retryCount - 1)
        }
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        let minSize = NSSize(width: 760, height: 520)
        window.styleMask.insert(.resizable)
        window.minSize = minSize
        window.contentMinSize = minSize

        if window.frame.size.width < minSize.width || window.frame.size.height < minSize.height {
            var frame = window.frame
            frame.size.width = max(frame.size.width, minSize.width)
            frame.size.height = max(frame.size.height, minSize.height)
            window.setFrame(frame, display: true, animate: false)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private struct OptionalKeyboardShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}
