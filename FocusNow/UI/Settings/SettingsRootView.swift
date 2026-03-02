import AppKit
import Combine
import SwiftData
import SwiftUI

struct SettingsRootView: View {
    enum Tab: String, CaseIterable, Hashable {
        case profiles
        case websites
        case apps
        case timer
        case schedules
        case stats

        var title: String {
            switch self {
            case .profiles: return "Profiles"
            case .websites: return "Websites"
            case .apps: return "Apps"
            case .timer: return "Timer"
            case .schedules: return "Schedules"
            case .stats: return "Stats"
            }
        }

        var systemImage: String {
            switch self {
            case .profiles: return "person.2"
            case .websites: return "globe"
            case .apps: return "app"
            case .timer: return "timer"
            case .schedules: return "calendar"
            case .stats: return "chart.bar"
            }
        }
    }

    @State private var selectedTab: Tab = .profiles

    var body: some View {
        VStack(spacing: 14) {
            settingsNavBar

            selectedTabView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 520)
        .padding()
    }

    private var settingsNavBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { tab in
                settingsTabButton(for: tab)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func settingsTabButton(for tab: Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                selectedTab = tab
            }
        } label: {
            Label(tab.title, systemImage: tab.systemImage)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.26) : Color.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.45),
                            lineWidth: isSelected ? 1.0 : 0.8
                        )
                )
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .pointingHandCursor()
    }

    @ViewBuilder
    private var selectedTabView: some View {
        switch selectedTab {
        case .profiles:
            ProfilesSettingsView()
        case .websites:
            WebsiteRulesSettingsView()
        case .apps:
            AppRulesSettingsView()
        case .timer:
            TimerSettingsView()
        case .schedules:
            SchedulesSettingsView()
        case .stats:
            StatsSettingsView()
        }
    }
}

private struct SettingsPagePalette {
    let backgroundStart: Color
    let backgroundEnd: Color
    let cardFill: Color
    let cardStroke: Color
    let cardShadow: Color
    let chipFill: Color
    let chipStroke: Color
    let secondarySurface: Color
    let secondarySurfaceStroke: Color
    let contributionEmpty: Color
    let contributionStroke: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            backgroundStart = Color(red: 0.14, green: 0.15, blue: 0.18)
            backgroundEnd = Color(red: 0.09, green: 0.10, blue: 0.12)
            cardFill = Color(red: 0.17, green: 0.18, blue: 0.22).opacity(0.92)
            cardStroke = Color.white.opacity(0.08)
            cardShadow = Color.black.opacity(0.28)
            chipFill = Color.white.opacity(0.08)
            chipStroke = Color.white.opacity(0.06)
            secondarySurface = Color.white.opacity(0.06)
            secondarySurfaceStroke = Color.white.opacity(0.08)
            contributionEmpty = Color(red: 0.22, green: 0.24, blue: 0.28)
            contributionStroke = Color.white.opacity(0.05)
        } else {
            backgroundStart = Color(red: 0.95, green: 0.95, blue: 0.96)
            backgroundEnd = Color(red: 0.91, green: 0.92, blue: 0.93)
            cardFill = Color.white.opacity(0.78)
            cardStroke = Color.white.opacity(0.92)
            cardShadow = Color.black.opacity(0.04)
            chipFill = Color.white.opacity(0.72)
            chipStroke = Color.white.opacity(0.95)
            secondarySurface = Color.white.opacity(0.6)
            secondarySurfaceStroke = Color.black.opacity(0.08)
            contributionEmpty = Color(red: 0.92, green: 0.93, blue: 0.94)
            contributionStroke = Color.black.opacity(0.06)
        }
    }
}

private struct ProfilesSettingsView: View {
    private let maxProfileCount = 5

    struct ProfileRow: Identifiable {
        let id: UUID
        let name: String
        let isActive: Bool
        let model: Profile
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query(sort: \Profile.name) private var profiles: [Profile]

    @State private var profileName: String = ""
    @State private var selectedProfileID: UUID?

    private var profileRows: [ProfileRow] {
        profiles
            .map { profile in
                ProfileRow(
                    id: profile.id,
                    name: profile.name,
                    isActive: coordinator.activeProfile?.id == profile.id,
                    model: profile
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedProfile: ProfileRow? {
        guard let selectedProfileID else { return nil }
        return profileRows.first { $0.id == selectedProfileID }
    }

    private var hasReachedProfileLimit: Bool {
        profiles.count >= maxProfileCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Profiles")
                    .font(.title2)
                Spacer()
            }

            Table(profileRows, selection: $selectedProfileID) {
                TableColumn("Profile") { row in
                    Text(row.name)
                }
                TableColumn("Status") { row in
                    if row.isActive {
                        Text("Active")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Use") {
                            coordinator.makeProfileActive(row.model)
                        }
                        .buttonStyle(.borderless)
                        .pointingHandCursor()
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                TextField("New profile", text: $profileName)
                    .disabled(hasReachedProfileLimit)
                Button("Add") {
                    addProfile()
                }
                .disabled(
                    profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasReachedProfileLimit
                )
                .pointingHandCursor()
            }

            if hasReachedProfileLimit {
                Text("Maximum of 5 profiles reached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Use Selected") {
                    useSelectedProfile()
                }
                .disabled(selectedProfile == nil)
                .pointingHandCursor()

                Button("Delete Selected") {
                    deleteSelectedProfile()
                }
                .disabled(selectedProfile == nil)
                .pointingHandCursor()
            }
        }
        .onAppear {
            coordinator.reloadProfiles()
        }
    }

    private func addProfile() {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard profiles.count < maxProfileCount else { return }

        let profile = Profile(name: trimmed)
        modelContext.insert(profile)
        modelContext.insert(TimerConfig(profileID: profile.id))
        try? modelContext.save()
        profileName = ""
        coordinator.reloadProfiles()
    }

    private func useSelectedProfile() {
        guard let selectedProfile else { return }
        coordinator.makeProfileActive(selectedProfile.model)
    }

    private func deleteSelectedProfile() {
        guard let selectedProfile else { return }
        modelContext.delete(selectedProfile.model)
        try? modelContext.save()
        selectedProfileID = nil
        coordinator.reloadProfiles()
    }
}

private struct WebsiteRulesSettingsView: View {
    struct WebsiteRow: Identifiable {
        let id: UUID
        let website: String
        let status: String
        let model: WebsiteRule
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var websiteRules: [WebsiteRule]

    @State private var pattern = ""
    @State private var selectedRuleID: UUID?

    private var activeRules: [WebsiteRule] {
        guard let profileID = coordinator.activeProfile?.id else { return [] }
        return websiteRules.filter { $0.profileID == profileID }
    }

    private var websiteRows: [WebsiteRow] {
        activeRules
            .map { rule in
                WebsiteRow(
                    id: rule.id,
                    website: rule.pattern,
                    status: rule.isEnabled ? "Blocked" : "Disabled",
                    model: rule
                )
            }
            .sorted { $0.website.localizedCaseInsensitiveCompare($1.website) == .orderedAscending }
    }

    private var selectedWebsiteRow: WebsiteRow? {
        guard let selectedRuleID else { return nil }
        return websiteRows.first { $0.id == selectedRuleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(websiteRows, selection: $selectedRuleID) {
                TableColumn("Website") { row in
                    Text(row.website)
                }
                TableColumn("Status") { row in
                    Text(row.status)
                        .foregroundStyle(row.status == "Blocked" ? .primary : .secondary)
                }
            }
            .frame(maxHeight: .infinity)

            Label("Website blocking supports only Chromium- and Safari-based browsers.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            if coordinator.activeProfile == nil {
                Text("Select an active profile to manage blocked websites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("example.com", text: $pattern)
                Button("Add") { addRule() }
                    .disabled(
                        coordinator.activeProfile == nil
                            || pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .pointingHandCursor()

                Button("Delete Selected") {
                    deleteSelectedRule()
                }
                .disabled(selectedWebsiteRow == nil)
                .pointingHandCursor()
            }
        }
    }

    private func addRule() {
        guard let profileID = coordinator.activeProfile?.id else { return }
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        modelContext.insert(WebsiteRule(profileID: profileID, pattern: trimmed, kind: .suffixDomain, mode: .blocklist))
        try? modelContext.save()
        pattern = ""
    }

    private func deleteSelectedRule() {
        guard let selectedWebsiteRow else { return }
        modelContext.delete(selectedWebsiteRow.model)
        try? modelContext.save()
        selectedRuleID = nil
    }
}

private struct AppRulesSettingsView: View {
    struct BlockedAppRow: Identifiable {
        let id: UUID
        let displayName: String
        let model: BlockedAppRule
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var appRules: [BlockedAppRule]

    @State private var installedApps: [InstalledApp] = []
    @State private var searchQuery: String = ""

    private let appRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var activeRules: [BlockedAppRule] {
        guard let profileID = coordinator.activeProfile?.id else { return [] }
        return appRules.filter { $0.profileID == profileID }
    }

    private var blockedRows: [BlockedAppRow] {
        activeRules
            .map { rule in
                BlockedAppRow(
                    id: rule.id,
                    displayName: rule.displayName,
                    model: rule
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var blockedBundleIdentifiers: Set<String> {
        Set(activeRules.map(\.bundleIdentifier))
    }

    private var filteredInstalledApps: [InstalledApp] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleApps = installedApps.filter { app in
            !blockedBundleIdentifiers.contains(app.bundleIdentifier)
        }
        guard !query.isEmpty else { return visibleApps }

        return visibleApps.filter { app in
            app.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            blockedAppsSection
            installedAppsSection
        }
        .onAppear {
            if installedApps.isEmpty {
                refreshInstalledApps()
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshInstalledApps()
        }
        .onReceive(appRefreshTimer) { _ in
            refreshInstalledApps()
        }
    }

    private var blockedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blocked Apps")
                .font(.headline)

            if blockedRows.isEmpty {
                Text("No blocked apps")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                Table(blockedRows) {
                    TableColumn("App") { row in
                        Text(row.displayName)
                    }
                    TableColumn("Blocked") { row in
                        Button("Unblock") {
                            modelContext.delete(row.model)
                            try? modelContext.save()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .pointingHandCursor()
                    }
                    .width(110)
                }
                .frame(minHeight: 140, maxHeight: 180)
            }
        }
    }

    private var installedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Installed Apps")
                    .font(.headline)
                Spacer()
                TextField("Search apps", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            if coordinator.activeProfile == nil {
                ContentUnavailableView("No Active Profile", systemImage: "person.crop.circle.badge.exclamationmark")
            } else if installedApps.isEmpty {
                ContentUnavailableView("No Apps Detected", systemImage: "app.badge")
            } else {
                Table(filteredInstalledApps) {
                    TableColumn("App") { app in
                        Text(app.displayName)
                    }
                    TableColumn("Block") { app in
                        Button(blockedBundleIdentifiers.contains(app.bundleIdentifier) ? "Blocked" : "Block") {
                            toggleBlockedState(for: app)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(blockedBundleIdentifiers.contains(app.bundleIdentifier) ? .red : .accentColor)
                        .pointingHandCursor()
                    }
                    .width(110)
                }
            }
        }
    }

    private func refreshInstalledApps() {
        installedApps = InstalledAppCatalog.discover()
    }

    private func toggleBlockedState(for app: InstalledApp) {
        guard let profileID = coordinator.activeProfile?.id else { return }

        if let existing = activeRules.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(
                BlockedAppRule(
                    profileID: profileID,
                    bundleIdentifier: app.bundleIdentifier,
                    displayName: app.displayName
                )
            )
        }
        try? modelContext.save()
    }
}

private struct TimerSettingsView: View {
    private struct TimerPreset: Identifiable, Hashable {
        let kind: TimerPresetKind
        let title: String
        let subtitle: String
        let work: Int?
        let shortBreak: Int?
        let longBreak: Int?
        let rounds: Int?

        var id: String { kind.rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var timerConfigs: [TimerConfig]

    @State private var workMinutes = 25
    @State private var shortBreakMinutes = 5
    @State private var longBreakMinutes = 15
    @State private var roundsBeforeLongBreak = 4
    @State private var autoStopAfterRounds = 0
    @State private var lockedMode = false
    @State private var pin = ""
    @State private var selectedPreset: TimerPresetKind = .pomodoro
    @State private var isLoadingConfig = false

    private let presets: [TimerPreset] = [
        TimerPreset(
            kind: .pomodoro,
            title: "Pomodoro",
            subtitle: "25 / 5 / 15",
            work: 25,
            shortBreak: 5,
            longBreak: 15,
            rounds: 4
        ),
        TimerPreset(
            kind: .deepWork,
            title: "Deep Work",
            subtitle: "50 / 10 / 20",
            work: 50,
            shortBreak: 10,
            longBreak: 20,
            rounds: 3
        ),
        TimerPreset(
            kind: .sprint,
            title: "Sprint",
            subtitle: "15 / 3 / 10",
            work: 15,
            shortBreak: 3,
            longBreak: 10,
            rounds: 4
        ),
        TimerPreset(
            kind: .custom,
            title: "Custom",
            subtitle: "Edit durations manually",
            work: nil,
            shortBreak: nil,
            longBreak: nil,
            rounds: nil
        )
    ]

    private var activeConfig: TimerConfig? {
        guard let profileID = coordinator.activeProfile?.id else { return nil }
        return timerConfigs.first { $0.profileID == profileID }
    }

    private var cycleEstimateMinutes: Int {
        let shortBreakCount = max(0, roundsBeforeLongBreak - 1)
        return (workMinutes * roundsBeforeLongBreak) + (shortBreakMinutes * shortBreakCount) + longBreakMinutes
    }

    private var autoStopSummary: String {
        autoStopAfterRounds > 0 ? "\(autoStopAfterRounds) rounds" : "Off"
    }

    private var configuredTotalTimeText: String {
        guard let totalMinutes = configuredTotalMinutes else { return "∞" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(minutes)m"
    }

    private var configuredTotalMinutes: Int? {
        guard autoStopAfterRounds > 0 else { return nil }

        let completedRoundsBeforeStop = autoStopAfterRounds
        let longBreaksBeforeStop = max(0, (completedRoundsBeforeStop - 1) / max(1, roundsBeforeLongBreak))
        let totalBreaksBeforeStop = max(0, completedRoundsBeforeStop - 1)
        let shortBreaksBeforeStop = max(0, totalBreaksBeforeStop - longBreaksBeforeStop)

        return (completedRoundsBeforeStop * workMinutes)
            + (shortBreaksBeforeStop * shortBreakMinutes)
            + (longBreaksBeforeStop * longBreakMinutes)
    }

    private var isCustomPreset: Bool {
        selectedPreset == .custom
    }

    private var palette: SettingsPagePalette {
        SettingsPagePalette(colorScheme: colorScheme)
    }

    var body: some View {
        timerContent
    }

    private var timerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Timer")
                    .font(.title2.weight(.semibold))

                if activeConfig == nil {
                    ContentUnavailableView(
                        "No Active Profile",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Select an active profile to configure timer settings.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    timerOverviewCard
                    timerPresetsCard
                    timingCard
                    cycleCard
                    securityCard
                    startupCard
                    Text("Changes save automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.backgroundStart,
                            palette.backgroundEnd
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear(perform: load)
        .modifier(TimerAutoSaveModifier(view: self))
    }

    private struct TimerAutoSaveModifier: ViewModifier {
        let view: TimerSettingsView

        func body(content: Content) -> some View {
            content
                .onChange(of: view.coordinator.activeProfile?.id) {
                    view.load()
                }
                .onChange(of: view.timerConfigs.count) {
                    view.load()
                }
                .onChange(of: view.workMinutes) {
                    view.saveAutomatically()
                }
                .onChange(of: view.shortBreakMinutes) {
                    view.saveAutomatically()
                }
                .onChange(of: view.longBreakMinutes) {
                    view.saveAutomatically()
                }
                .onChange(of: view.roundsBeforeLongBreak) {
                    view.saveAutomatically()
                }
                .onChange(of: view.autoStopAfterRounds) {
                    view.saveAutomatically()
                }
                .onChange(of: view.lockedMode) {
                    view.saveAutomatically()
                }
                .onChange(of: view.selectedPreset) {
                    view.saveAutomatically()
                }
        }
    }

    private var timerOverviewCard: some View {
        card(title: "Current Plan", icon: "hourglass.bottomhalf.filled") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(workMinutes)m")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("focus")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                summaryPill(text: "Short break \(shortBreakMinutes)m")
                summaryPill(text: "Long break \(longBreakMinutes)m")
                summaryPill(text: "\(roundsBeforeLongBreak) rounds/cycle")
                summaryPill(text: "Total \(configuredTotalTimeText)")
            }

            Text("One full cycle is about \(cycleEstimateMinutes) minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var timerPresetsCard: some View {
        card(title: "Presets", icon: "wand.and.stars") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(presets) { preset in
                    let selected = selectedPreset == preset.kind
                    Button {
                        selectPreset(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.title)
                                .font(.subheadline.weight(.semibold))
                            Text(preset.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.18) : palette.secondarySurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    selected ? Color.accentColor.opacity(colorScheme == .dark ? 0.78 : 0.65) : palette.secondarySurfaceStroke,
                                    lineWidth: selected ? 1.2 : 0.8
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
    }

    private var timingCard: some View {
        card(title: "Durations", icon: "clock.badge") {
            minuteStepperRow(title: "Work", value: $workMinutes, range: 1...180)
            minuteStepperRow(title: "Short break", value: $shortBreakMinutes, range: 1...30)
            minuteStepperRow(title: "Long break", value: $longBreakMinutes, range: 1...60)

            if !isCustomPreset {
                Text("Switch to Custom preset to edit durations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!isCustomPreset)
        .opacity(isCustomPreset ? 1 : 0.52)
    }

    private var cycleCard: some View {
        card(title: "Cycle Rules", icon: "arrow.triangle.2.circlepath") {
            Stepper(value: $roundsBeforeLongBreak, in: 2...10) {
                rowLabel(title: "Rounds before long break", value: "\(roundsBeforeLongBreak)")
            }
            .disabled(!isCustomPreset)
            .opacity(isCustomPreset ? 1 : 0.52)

            Stepper(value: $autoStopAfterRounds, in: 0...24) {
                rowLabel(title: "Auto-stop after rounds", value: autoStopSummary)
            }
        }
    }

    private var securityCard: some View {
        card(title: "Session Safety", icon: "lock.shield") {
            Toggle("Locked mode", isOn: $lockedMode)

            HStack(spacing: 8) {
                SecureField("Set/Update PIN", text: $pin)
                    .textFieldStyle(.roundedBorder)

                Button("Save PIN") {
                    coordinator.savePIN(pin)
                    pin = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .pointingHandCursor()
            }
        }
    }

    private var startupCard: some View {
        card(title: "System", icon: "switch.2") {
            Toggle("Launch at login", isOn: Binding(get: {
                coordinator.appSettings()?.launchAtLoginEnabled ?? false
            }, set: { value in
                coordinator.setLaunchAtLogin(enabled: value)
            }))
        }
    }

    private func card<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.cardStroke, lineWidth: 1)
        )
        .shadow(color: palette.cardShadow, radius: 8, y: 3)
    }

    private func minuteStepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range) {
            rowLabel(title: title, value: "\(value.wrappedValue) min")
        }
    }

    private func rowLabel(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func summaryPill(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.chipFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(palette.chipStroke, lineWidth: 0.8)
            )
    }

    private func selectPreset(_ preset: TimerPreset) {
        selectedPreset = preset.kind
        applyPresetValues(for: preset.kind, animated: true)
    }

    private func applyPresetValues(for preset: TimerPresetKind, animated: Bool) {
        guard let presetValues = presetValues(for: preset) else { return }

        let apply = {
            workMinutes = presetValues.work
            shortBreakMinutes = presetValues.shortBreak
            longBreakMinutes = presetValues.longBreak
            roundsBeforeLongBreak = presetValues.rounds
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.18), apply)
        } else {
            apply()
        }
    }

    private func presetValues(for preset: TimerPresetKind) -> (work: Int, shortBreak: Int, longBreak: Int, rounds: Int)? {
        switch preset {
        case .pomodoro:
            return (25, 5, 15, 4)
        case .deepWork:
            return (50, 10, 20, 3)
        case .sprint:
            return (15, 3, 10, 4)
        case .custom:
            return nil
        }
    }

    private func load() {
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        guard let config = activeConfig else { return }
        selectedPreset = config.preset

        workMinutes = max(1, config.workSeconds / 60)
        shortBreakMinutes = max(1, config.shortBreakSeconds / 60)
        longBreakMinutes = max(1, config.longBreakSeconds / 60)
        roundsBeforeLongBreak = max(1, config.roundsBeforeLongBreak)
        autoStopAfterRounds = max(0, config.maxFocusRounds ?? 0)
        lockedMode = config.lockedModeEnabled

        if selectedPreset != .custom {
            applyPresetValues(for: selectedPreset, animated: false)
        }
    }

    private func saveAutomatically() {
        guard !isLoadingConfig else { return }
        save()
    }

    private func save() {
        guard let config = activeConfig else { return }

        if selectedPreset != .custom {
            applyPresetValues(for: selectedPreset, animated: false)
        }

        config.workSeconds = workMinutes * 60
        config.shortBreakSeconds = shortBreakMinutes * 60
        config.longBreakSeconds = longBreakMinutes * 60
        config.roundsBeforeLongBreak = roundsBeforeLongBreak
        config.maxFocusRounds = autoStopAfterRounds > 0 ? autoStopAfterRounds : nil
        config.lockedModeEnabled = lockedMode
        config.preset = selectedPreset
        try? modelContext.save()
        coordinator.reloadIdleTimerDisplay()
    }
}

private struct SchedulesSettingsView: View {
    struct ScheduleRow: Identifiable {
        let id: UUID
        let recurrence: String
        let days: String
        let time: String
        let model: ScheduleRule
    }

    enum Meridiem: String, CaseIterable, Identifiable {
        case am = "AM"
        case pm = "PM"

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var schedules: [ScheduleRule]

    @State private var recurrence: ScheduleRecurrence = .weekdays
    @State private var hourInput = "9"
    @State private var minuteInput = "00"
    @State private var meridiem: Meridiem = .am
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var selectedScheduleID: UUID?

    private let scheduleFormSpacing: CGFloat = 8
    private let recurrencePickerWidth: CGFloat = 180

    private var activeSchedules: [ScheduleRule] {
        guard let profileID = coordinator.activeProfile?.id else { return [] }
        return schedules
            .filter { $0.profileID == profileID }
            .sorted { $0.startTimeMinuteOfDay < $1.startTimeMinuteOfDay }
    }

    private var scheduleRows: [ScheduleRow] {
        activeSchedules.map { schedule in
            ScheduleRow(
                id: schedule.id,
                recurrence: recurrenceTitle(for: schedule),
                days: weekdaySummary(for: schedule),
                time: formatTime(schedule.startTimeMinuteOfDay),
                model: schedule
            )
        }
    }

    private var selectedSchedule: ScheduleRow? {
        guard let selectedScheduleID else { return nil }
        return scheduleRows.first { $0.id == selectedScheduleID }
    }

    private var canAddSchedule: Bool {
        (recurrence != .customWeekdays || !selectedWeekdays.isEmpty)
            && parseHour(hourInput) != nil
            && parseMinute(minuteInput) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedules")
                .font(.title2)

            Table(scheduleRows, selection: $selectedScheduleID) {
                TableColumn("Recurrence") { row in
                    Text(row.recurrence)
                }
                TableColumn("Days") { row in
                    Text(row.days)
                        .foregroundStyle(.secondary)
                }
                TableColumn("Time") { row in
                    Text(row.time)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: scheduleFormSpacing) {
                Picker("Recurrence", selection: $recurrence) {
                    ForEach(ScheduleRecurrence.allCases) { item in
                        Text(recurrenceLabel(for: item)).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: recurrencePickerWidth, alignment: .leading)

                HStack(spacing: 4) {
                    TextField("", text: $hourInput)
                        .frame(width: 32)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)

                    Text(":")
                        .font(.body.monospacedDigit())

                    TextField("", text: $minuteInput)
                        .frame(width: 38)
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                }
                .font(.body.monospacedDigit())

                Picker("", selection: $meridiem) {
                    ForEach(Meridiem.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 96)

                Button("Add") { addSchedule() }
                    .disabled(coordinator.activeProfile == nil || !canAddSchedule)
                    .pointingHandCursor()
                Button("Delete Selected", role: .destructive) {
                    deleteSelectedSchedule()
                }
                .disabled(selectedSchedule == nil)
                .pointingHandCursor()
            }

            if recurrence == .customWeekdays {
                HStack(spacing: 8) {
                    ForEach(weekdayOptions, id: \.number) { day in
                        Button(day.label) {
                            toggleWeekday(day.number)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(selectedWeekdays.contains(day.number) ? .accentColor : .gray.opacity(0.45))
                        .pointingHandCursor()
                    }
                }
                .padding(.leading, recurrencePickerWidth + scheduleFormSpacing)
            }
        }
        .onAppear {
            coordinator.reloadSchedules()
        }
    }

    private var weekdayOptions: [(number: Int, label: String)] {
        [
            (2, "Mon"),
            (3, "Tue"),
            (4, "Wed"),
            (5, "Thu"),
            (6, "Fri"),
            (7, "Sat"),
            (1, "Sun")
        ]
    }

    private func toggleWeekday(_ day: Int) {
        if selectedWeekdays.contains(day) {
            selectedWeekdays.remove(day)
        } else {
            selectedWeekdays.insert(day)
        }
    }

    private func addSchedule() {
        guard let profileID = coordinator.activeProfile?.id else { return }
        guard canAddSchedule else { return }
        guard let hour12 = parseHour(hourInput), let minute = parseMinute(minuteInput) else { return }

        let hour24 = to24Hour(hour12: hour12, meridiem: meridiem)
        let minutes = hour24 * 60 + minute
        let weekdays = recurrence == .customWeekdays ? selectedWeekdays.sorted() : []
        modelContext.insert(
            ScheduleRule(
                profileID: profileID,
                recurrence: recurrence,
                weekdayNumbers: weekdays,
                startTimeMinuteOfDay: minutes
            )
        )
        try? modelContext.save()
        hourInput = "\(hour12)"
        minuteInput = String(format: "%02d", minute)
        coordinator.reloadSchedules()
    }

    private func deleteSelectedSchedule() {
        guard let selectedSchedule else { return }
        modelContext.delete(selectedSchedule.model)
        try? modelContext.save()
        selectedScheduleID = nil
        coordinator.reloadSchedules()
    }

    private func to24Hour(hour12: Int, meridiem: Meridiem) -> Int {
        let base = hour12 % 12
        return meridiem == .pm ? base + 12 : base
    }

    private func parseHour(_ input: String) -> Int? {
        guard let value = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...12).contains(value)
        else {
            return nil
        }

        return value
    }

    private func parseMinute(_ input: String) -> Int? {
        guard let value = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...59).contains(value)
        else {
            return nil
        }

        return value
    }

    private func formatTime(_ minuteOfDay: Int) -> String {
        let hour24 = minuteOfDay / 60
        let minute = minuteOfDay % 60
        let meridiem = hour24 >= 12 ? "PM" : "AM"
        let hour12 = ((hour24 + 11) % 12) + 1
        return String(format: "%d:%02d %@", hour12, minute, meridiem)
    }

    private func recurrenceLabel(for recurrence: ScheduleRecurrence) -> String {
        switch recurrence {
        case .customWeekdays:
            return "Custom"
        case .daily:
            return "Daily"
        case .weekdays:
            return "Weekdays"
        case .weekends:
            return "Weekends"
        }
    }

    private func recurrenceTitle(for schedule: ScheduleRule) -> String {
        if schedule.recurrence != .customWeekdays {
            return schedule.recurrence.rawValue.capitalized
        }

        return "Custom"
    }

    private func weekdaySummary(for schedule: ScheduleRule) -> String {
        guard schedule.recurrence == .customWeekdays else {
            return "-"
        }

        let mapping: [Int: String] = [
            1: "Sun",
            2: "Mon",
            3: "Tue",
            4: "Wed",
            5: "Thu",
            6: "Fri",
            7: "Sat"
        ]

        let days = schedule.weekdayNumbers
            .compactMap { mapping[$0] }
            .joined(separator: ", ")

        return days.isEmpty ? "-" : days
    }
}

private struct StatsSettingsView: View {
    private struct ProfileSlice: Identifiable {
        let profileID: UUID
        let name: String
        let seconds: Int
        let color: Color

        var id: UUID { profileID }
    }

    private struct HeatmapDay: Identifiable {
        let date: Date
        let seconds: Int
        let isInCurrentYear: Bool
        let level: Int

        var id: Date { date }
    }

    private struct HeatmapModel {
        let weeks: [[HeatmapDay]]
    }

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query(sort: \Profile.name) private var profiles: [Profile]
    @Query(sort: \SessionRecord.startedAt) private var sessionRecords: [SessionRecord]

    private let profilePalette: [Color] = [
        Color(red: 0.31, green: 0.46, blue: 0.78),
        Color(red: 0.21, green: 0.61, blue: 0.56),
        Color(red: 0.52, green: 0.45, blue: 0.76),
        Color(red: 0.83, green: 0.59, blue: 0.38),
        Color(red: 0.42, green: 0.68, blue: 0.42),
        Color(red: 0.28, green: 0.59, blue: 0.76)
    ]

    private let heatmapCellSize: CGFloat = 11
    private let heatmapCellSpacing: CGFloat = 3

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    private var currentYear: Int {
        calendar.component(.year, from: .now)
    }

    private var yearRange: (start: Date, end: Date) {
        let start = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1)) ?? calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? .now
        return (start, end)
    }

    private var yearRecords: [SessionRecord] {
        let range = yearRange
        return sessionRecords.filter { $0.startedAt >= range.start && $0.startedAt < range.end }
    }

    private var palette: SettingsPagePalette {
        SettingsPagePalette(colorScheme: colorScheme)
    }

    private var totalYearSeconds: Int {
        yearRecords.reduce(0) { $0 + $1.durationSeconds }
    }

    private var totalYearPomodoros: Int {
        yearRecords.reduce(0) { $0 + $1.completedPomodoros }
    }

    private var activeYearDays: Int {
        Set(yearRecords.map { calendar.startOfDay(for: $0.startedAt) }).count
    }

    private var monthSeconds: Int {
        coordinator.sessionTotalsForCurrentMonth()
    }

    private var averageDailyMinutes: Int {
        guard activeYearDays > 0 else { return 0 }
        return (totalYearSeconds / 60) / activeYearDays
    }

    private var profileNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) })
    }

    private var profileSlices: [ProfileSlice] {
        let totals = Dictionary(grouping: yearRecords, by: \.profileID)
            .mapValues { rows in rows.reduce(0) { $0 + $1.durationSeconds } }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }

        return totals.enumerated().map { index, entry in
            ProfileSlice(
                profileID: entry.key,
                name: profileNameByID[entry.key] ?? "Unknown Profile",
                seconds: entry.value,
                color: profilePalette[index % profilePalette.count]
            )
        }
    }

    private var heatmapModel: HeatmapModel {
        let range = yearRange
        let totalsByDay = Dictionary(grouping: yearRecords, by: { calendar.startOfDay(for: $0.startedAt) })
            .mapValues { rows in rows.reduce(0) { $0 + $1.durationSeconds } }

        let start = startOfWeek(for: range.start)
        let lastYearDay = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.start
        let end = calendar.date(byAdding: .day, value: 6, to: startOfWeek(for: lastYearDay)) ?? lastYearDay

        var rawDays: [(date: Date, seconds: Int, isInYear: Bool)] = []
        var cursor = start
        while cursor <= end {
            let inYear = cursor >= range.start && cursor < range.end
            rawDays.append((cursor, totalsByDay[cursor] ?? 0, inYear))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }

        let cells = rawDays.map { item in
            HeatmapDay(
                date: item.date,
                seconds: item.seconds,
                isInCurrentYear: item.isInYear,
                level: intensityLevel(seconds: item.seconds, isInCurrentYear: item.isInYear)
            )
        }

        var weeks: [[HeatmapDay]] = []
        var index = 0
        while index < cells.count {
            weeks.append(Array(cells[index ..< min(index + 7, cells.count)]))
            index += 7
        }

        return HeatmapModel(weeks: weeks)
    }

    var body: some View {
        let model = heatmapModel

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Stats")
                    .font(.title2.weight(.semibold))

                statsOverviewCard
                profileSplitCard
                contributionCard(model: model)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.backgroundStart,
                            palette.backgroundEnd
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statsOverviewCard: some View {
        dashboardCard(
            title: "Focus Overview",
            subtitle: nil
        ) {
            HStack(alignment: .top, spacing: 10) {
                metricTile(label: "This Month", value: formatDuration(monthSeconds))
                metricTile(label: "This Year", value: formatDuration(totalYearSeconds))
                metricTile(label: "Streak", value: "\(coordinator.streakCount())d")
                metricTile(label: "Active Days", value: "\(activeYearDays)")
                metricTile(label: "Avg / Day", value: "\(averageDailyMinutes)m")
            }
        }
    }

    private var profileSplitCard: some View {
        dashboardCard(
            title: "Profile Distribution",
            subtitle: "How your focus time is split across profiles"
        ) {
            if profileSlices.isEmpty {
                Text("No focus sessions recorded yet for \(currentYear).")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else {
                HStack(spacing: 18) {
                    ZStack {
                        ForEach(profileSlices.indices, id: \.self) { index in
                            let range = donutAngles(for: index)
                            DonutSegmentShape(startAngle: range.start, endAngle: range.end, thickness: 36)
                                .fill(profileSlices[index].color.gradient)
                                .shadow(color: profileSlices[index].color.opacity(0.22), radius: 5, y: 2)
                        }

                        VStack(spacing: 4) {
                            Text(formatHours(totalYearSeconds))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("\(totalYearPomodoros) rounds")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 210, height: 210)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(profileSlices) { slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 9, height: 9)
                                Text(slice.name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(percentageText(for: slice.seconds))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                Text(formatHours(slice.seconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .trailing)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func contributionCard(model: HeatmapModel) -> some View {
        let gridHeight = (CGFloat(7) * heatmapCellSize) + (CGFloat(6) * heatmapCellSpacing)

        return dashboardCard(
            title: "Yearly Overview",
            subtitle: "Daily focus intensity map"
        ) {
            GeometryReader { geometry in
                let columnCount = max(1, model.weeks.count)
                let totalSpacing = CGFloat(columnCount - 1) * heatmapCellSpacing
                let availableWidth = max(1, geometry.size.width - totalSpacing)
                let dynamicCellSize = max(4, min(heatmapCellSize, floor(availableWidth / CGFloat(columnCount))))
                let cornerRadius = max(1.8, dynamicCellSize * 0.2)

                HStack(alignment: .top, spacing: heatmapCellSpacing) {
                    ForEach(model.weeks.indices, id: \.self) { weekIndex in
                        VStack(spacing: heatmapCellSpacing) {
                            ForEach(model.weeks[weekIndex]) { day in
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(contributionColor(for: day))
                                    .frame(width: dynamicCellSize, height: dynamicCellSize)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                            .strokeBorder(
                                                day.isInCurrentYear ? palette.contributionStroke : .clear,
                                                lineWidth: 0.4
                                            )
                                    )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: gridHeight)

            HStack(spacing: 6) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                        .fill(contributionLegendColor(level: level))
                        .frame(width: heatmapCellSize, height: heatmapCellSize)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                                .strokeBorder(palette.contributionStroke, lineWidth: 0.4)
                        )
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func dashboardCard<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.cardStroke, lineWidth: 1)
        )
        .shadow(color: palette.cardShadow, radius: 10, y: 4)
    }

    private func metricTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func donutAngles(for index: Int) -> (start: Angle, end: Angle) {
        let total = max(1, profileSlices.reduce(0) { $0 + $1.seconds })
        let previousSeconds = profileSlices.prefix(index).reduce(0) { $0 + $1.seconds }
        let currentSeconds = profileSlices[index].seconds

        let start = Angle.degrees((Double(previousSeconds) / Double(total)) * 360 - 90)
        let end = Angle.degrees((Double(previousSeconds + currentSeconds) / Double(total)) * 360 - 90)
        return (start, end)
    }

    private func startOfWeek(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func intensityLevel(seconds: Int, isInCurrentYear: Bool) -> Int {
        guard isInCurrentYear else { return -1 }
        guard seconds > 0 else { return 0 }

        let oneHour = 60 * 60
        let twoAndHalfHours = Int(Double(oneHour) * 2.5)
        let fiveHours = 5 * oneHour

        switch seconds {
        case ..<oneHour:
            return 1
        case ..<twoAndHalfHours:
            return 2
        case ..<fiveHours:
            return 3
        default:
            return 4
        }
    }

    private func contributionColor(for day: HeatmapDay) -> Color {
        guard day.isInCurrentYear else { return Color.clear }
        return contributionLegendColor(level: day.level)
    }

    private func contributionLegendColor(level: Int) -> Color {
        if colorScheme == .dark {
            switch level {
            case 0:
                return palette.contributionEmpty
            case 1:
                return Color(red: 0.28, green: 0.38, blue: 0.56)
            case 2:
                return Color(red: 0.35, green: 0.49, blue: 0.73)
            case 3:
                return Color(red: 0.43, green: 0.61, blue: 0.87)
            default:
                return Color(red: 0.55, green: 0.72, blue: 0.98)
            }
        }

        switch level {
        case 0:
            return palette.contributionEmpty
        case 1:
            return Color(red: 0.81, green: 0.87, blue: 0.98)
        case 2:
            return Color(red: 0.65, green: 0.76, blue: 0.95)
        case 3:
            return Color(red: 0.49, green: 0.64, blue: 0.90)
        default:
            return Color(red: 0.31, green: 0.46, blue: 0.78)
        }
    }

    private func percentageText(for seconds: Int) -> String {
        guard totalYearSeconds > 0 else { return "0%" }
        let percentage = (Double(seconds) / Double(totalYearSeconds)) * 100
        return String(format: "%.0f%%", percentage)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private func formatHours(_ seconds: Int) -> String {
        let hours = Double(seconds) / 3600.0
        return String(format: "%.1fh", hours)
    }
}

private struct DonutSegmentShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = max(0, outerRadius - thickness)

        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}
