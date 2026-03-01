import Foundation
import SwiftData

enum WebsiteRuleKind: String, Codable, CaseIterable, Identifiable {
    case exactDomain
    case suffixDomain
    case category

    var id: String { rawValue }
}

enum WebsiteRuleMode: String, Codable, CaseIterable, Identifiable {
    case blocklist
    case allowlist

    var id: String { rawValue }
}

enum ScheduleRecurrence: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekdays
    case weekends
    case customWeekdays

    var id: String { rawValue }
}

enum SessionEndedReason: String, Codable, CaseIterable, Identifiable {
    case completed
    case manualStop
    case lockedOverride
    case crashRecovery

    var id: String { rawValue }
}

enum TimerPresetKind: String, Codable, CaseIterable, Identifiable {
    case pomodoro
    case deepWork
    case sprint
    case custom

    var id: String { rawValue }
}

@Model
final class Profile {
    @Attribute(.unique) var id: UUID
    var name: String
    var isDefault: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TimerConfig {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var workSeconds: Int
    var shortBreakSeconds: Int
    var longBreakSeconds: Int
    var roundsBeforeLongBreak: Int
    var maxFocusRounds: Int?
    var lockedModeEnabled: Bool
    var presetRawValue: String?

    var preset: TimerPresetKind {
        get {
            if let presetRawValue,
               let preset = TimerPresetKind(rawValue: presetRawValue) {
                return preset
            }

            let work = workSeconds / 60
            let shortBreak = shortBreakSeconds / 60
            let longBreak = longBreakSeconds / 60
            let rounds = roundsBeforeLongBreak

            if work == 25 && shortBreak == 5 && longBreak == 15 && rounds == 4 {
                return .pomodoro
            }

            if work == 50 && shortBreak == 10 && longBreak == 20 && rounds == 3 {
                return .deepWork
            }

            if work == 15 && shortBreak == 3 && longBreak == 10 && rounds == 4 {
                return .sprint
            }

            return .custom
        }
        set {
            presetRawValue = newValue.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        profileID: UUID,
        workSeconds: Int = 1500,
        shortBreakSeconds: Int = 300,
        longBreakSeconds: Int = 900,
        roundsBeforeLongBreak: Int = 4,
        maxFocusRounds: Int? = nil,
        lockedModeEnabled: Bool = false,
        preset: TimerPresetKind = .pomodoro
    ) {
        self.id = id
        self.profileID = profileID
        self.workSeconds = workSeconds
        self.shortBreakSeconds = shortBreakSeconds
        self.longBreakSeconds = longBreakSeconds
        self.roundsBeforeLongBreak = roundsBeforeLongBreak
        self.maxFocusRounds = maxFocusRounds
        self.lockedModeEnabled = lockedModeEnabled
        self.presetRawValue = preset.rawValue
    }
}

@Model
final class WebsiteRule {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var pattern: String
    var kindRawValue: String
    var modeRawValue: String
    var isEnabled: Bool

    var kind: WebsiteRuleKind {
        get { WebsiteRuleKind(rawValue: kindRawValue) ?? .exactDomain }
        set { kindRawValue = newValue.rawValue }
    }

    var mode: WebsiteRuleMode {
        get { WebsiteRuleMode(rawValue: modeRawValue) ?? .blocklist }
        set { modeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        profileID: UUID,
        pattern: String,
        kind: WebsiteRuleKind = .exactDomain,
        mode: WebsiteRuleMode = .blocklist,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.profileID = profileID
        self.pattern = pattern
        self.kindRawValue = kind.rawValue
        self.modeRawValue = mode.rawValue
        self.isEnabled = isEnabled
    }
}

@Model
final class BlockedAppRule {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var bundleIdentifier: String
    var displayName: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        profileID: UUID,
        bundleIdentifier: String,
        displayName: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.profileID = profileID
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.isEnabled = isEnabled
    }
}

@Model
final class ScheduleRule {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var isEnabled: Bool
    var timezoneID: String
    var recurrenceRawValue: String
    var weekdayNumbers: [Int]
    var startTimeMinuteOfDay: Int
    var endTimeMinuteOfDay: Int?

    var recurrence: ScheduleRecurrence {
        get { ScheduleRecurrence(rawValue: recurrenceRawValue) ?? .daily }
        set { recurrenceRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        profileID: UUID,
        isEnabled: Bool = true,
        timezoneID: String = TimeZone.current.identifier,
        recurrence: ScheduleRecurrence = .daily,
        weekdayNumbers: [Int] = [],
        startTimeMinuteOfDay: Int,
        endTimeMinuteOfDay: Int? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.isEnabled = isEnabled
        self.timezoneID = timezoneID
        self.recurrenceRawValue = recurrence.rawValue
        self.weekdayNumbers = weekdayNumbers
        self.startTimeMinuteOfDay = startTimeMinuteOfDay
        self.endTimeMinuteOfDay = endTimeMinuteOfDay
    }
}

@Model
final class SessionRecord {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Int
    var completedPomodoros: Int
    var endedReasonRawValue: String
    var lockedOverrideUsed: Bool

    var endedReason: SessionEndedReason {
        get { SessionEndedReason(rawValue: endedReasonRawValue) ?? .manualStop }
        set { endedReasonRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        profileID: UUID,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        completedPomodoros: Int,
        endedReason: SessionEndedReason,
        lockedOverrideUsed: Bool
    ) {
        self.id = id
        self.profileID = profileID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.completedPomodoros = completedPomodoros
        self.endedReasonRawValue = endedReason.rawValue
        self.lockedOverrideUsed = lockedOverrideUsed
    }
}

@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var activeProfileID: UUID?
    var launchAtLoginEnabled: Bool
    var lockedPinReferenceKey: String?
    var quoteStyle: String
    var motivationalQuotesEnabled: Bool

    init(
        id: UUID = UUID(),
        activeProfileID: UUID? = nil,
        launchAtLoginEnabled: Bool = false,
        lockedPinReferenceKey: String? = "focusnow.locked.pin",
        quoteStyle: String = "classic",
        motivationalQuotesEnabled: Bool = true
    ) {
        self.id = id
        self.activeProfileID = activeProfileID
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.lockedPinReferenceKey = lockedPinReferenceKey
        self.quoteStyle = quoteStyle
        self.motivationalQuotesEnabled = motivationalQuotesEnabled
    }
}

struct TimerConfigSnapshot: Sendable {
    var workSeconds: Int
    var shortBreakSeconds: Int
    var longBreakSeconds: Int
    var roundsBeforeLongBreak: Int
    var maxFocusRounds: Int
    var lockedModeEnabled: Bool

    nonisolated static let `default` = TimerConfigSnapshot(
        workSeconds: 1500,
        shortBreakSeconds: 300,
        longBreakSeconds: 900,
        roundsBeforeLongBreak: 4,
        maxFocusRounds: 0,
        lockedModeEnabled: false
    )
}

struct WebsiteBlockingProfile: Sendable {
    var mode: WebsiteRuleMode
    var patterns: [String]
}

struct AppBlockingProfile: Sendable {
    var blockedBundleIdentifiers: Set<String>
}
