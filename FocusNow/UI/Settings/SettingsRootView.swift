import AppKit
import Combine
import SwiftData
import SwiftUI

struct SettingsRootView: View {
    enum Tab: Hashable {
        case profiles
        case websites
        case apps
        case timer
        case schedules
        case stats
    }

    @State private var selectedTab: Tab = .profiles

    var body: some View {
        TabView(selection: $selectedTab) {
            ProfilesSettingsView()
                .tabItem { Label("Profiles", systemImage: "person.2") }
                .tag(Tab.profiles)

            WebsiteRulesSettingsView()
                .tabItem { Label("Websites", systemImage: "globe") }
                .tag(Tab.websites)

            AppRulesSettingsView()
                .tabItem { Label("Apps", systemImage: "app") }
                .tag(Tab.apps)

            TimerSettingsView()
                .tabItem { Label("Timer", systemImage: "timer") }
                .tag(Tab.timer)

            SchedulesSettingsView()
                .tabItem { Label("Schedules", systemImage: "calendar") }
                .tag(Tab.schedules)

            StatsSettingsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(Tab.stats)
        }
        .frame(width: 760, height: 520)
        .padding()
    }
}

private struct ProfilesSettingsView: View {
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
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                TextField("New profile", text: $profileName)
                Button("Add") {
                    addProfile()
                }
                .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Button("Use Selected") {
                    useSelectedProfile()
                }
                .disabled(selectedProfile == nil)

                Button("Delete Selected") {
                    deleteSelectedProfile()
                }
                .disabled(selectedProfile == nil)
            }
        }
        .onAppear {
            coordinator.reloadProfiles()
        }
    }

    private func addProfile() {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

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

                Button("Delete Selected") {
                    deleteSelectedRule()
                }
                .disabled(selectedWebsiteRow == nil)
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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query private var timerConfigs: [TimerConfig]

    @State private var workMinutes = 25
    @State private var shortBreakMinutes = 5
    @State private var longBreakMinutes = 15
    @State private var roundsBeforeLongBreak = 4
    @State private var autoStopAfterRounds = 0
    @State private var lockedMode = false
    @State private var pin = ""

    private var activeConfig: TimerConfig? {
        guard let profileID = coordinator.activeProfile?.id else { return nil }
        return timerConfigs.first { $0.profileID == profileID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Timer")
                .font(.title2)

            Group {
                Stepper("Work: \(workMinutes) min", value: $workMinutes, in: 5...180)
                Stepper("Short break: \(shortBreakMinutes) min", value: $shortBreakMinutes, in: 1...30)
                Stepper("Long break: \(longBreakMinutes) min", value: $longBreakMinutes, in: 5...60)
                Stepper("Rounds before long break: \(roundsBeforeLongBreak)", value: $roundsBeforeLongBreak, in: 2...10)
                Stepper(
                    autoStopAfterRounds > 0
                        ? "Auto-stop after rounds: \(autoStopAfterRounds)"
                        : "Auto-stop after rounds: Off",
                    value: $autoStopAfterRounds,
                    in: 0...24
                )
                Toggle("Locked mode", isOn: $lockedMode)
            }

            HStack {
                SecureField("Set/Update PIN", text: $pin)
                Button("Save PIN") {
                    coordinator.savePIN(pin)
                    pin = ""
                }
                .disabled(pin.isEmpty)
            }

            HStack {
                Toggle("Launch at login", isOn: Binding(get: {
                    coordinator.appSettings()?.launchAtLoginEnabled ?? false
                }, set: { value in
                    coordinator.setLaunchAtLogin(enabled: value)
                }))

                Spacer()

                Button("Save Timer Settings") {
                    save()
                }
            }

            Spacer()
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let config = activeConfig else { return }
        workMinutes = max(1, config.workSeconds / 60)
        shortBreakMinutes = max(1, config.shortBreakSeconds / 60)
        longBreakMinutes = max(1, config.longBreakSeconds / 60)
        roundsBeforeLongBreak = max(1, config.roundsBeforeLongBreak)
        autoStopAfterRounds = max(0, config.maxFocusRounds ?? 0)
        lockedMode = config.lockedModeEnabled
    }

    private func save() {
        guard let config = activeConfig else { return }

        config.workSeconds = workMinutes * 60
        config.shortBreakSeconds = shortBreakMinutes * 60
        config.longBreakSeconds = longBreakMinutes * 60
        config.roundsBeforeLongBreak = roundsBeforeLongBreak
        config.maxFocusRounds = autoStopAfterRounds > 0 ? autoStopAfterRounds : nil
        config.lockedModeEnabled = lockedMode
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

            HStack {
                Picker("Recurrence", selection: $recurrence) {
                    ForEach(ScheduleRecurrence.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)

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
                Button("Delete Selected", role: .destructive) {
                    deleteSelectedSchedule()
                }
                .disabled(selectedSchedule == nil)
            }

            if recurrence == .customWeekdays {
                HStack(spacing: 8) {
                    ForEach(weekdayOptions, id: \.number) { day in
                        Button(day.label) {
                            toggleWeekday(day.number)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(selectedWeekdays.contains(day.number) ? .accentColor : .gray.opacity(0.45))
                    }
                }

                Text("Select one or more weekdays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stats")
                .font(.title2)

            statRow(title: "This Month", value: format(seconds: coordinator.sessionTotalsForCurrentMonth()))
            statRow(title: "Current Streak", value: "\(coordinator.streakCount()) days")

            Spacer()
        }
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func format(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
