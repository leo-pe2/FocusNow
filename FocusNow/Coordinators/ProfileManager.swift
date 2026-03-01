import Foundation
import SwiftData

@MainActor
final class ProfileManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func bootstrapDefaultsIfNeeded() throws -> Profile {
        if let existing = try fetchProfiles().first {
            return existing
        }

        let defaultProfile = Profile(name: "Deep Work", isDefault: true)
        modelContext.insert(defaultProfile)

        let timer = TimerConfig(profileID: defaultProfile.id)
        modelContext.insert(timer)

        let schedule = ScheduleRule(profileID: defaultProfile.id, recurrence: .weekdays, weekdayNumbers: [2, 3, 4, 5, 6], startTimeMinuteOfDay: 9 * 60)
        modelContext.insert(schedule)

        try modelContext.save()
        return defaultProfile
    }

    func fetchProfiles() throws -> [Profile] {
        let descriptor = FetchDescriptor<Profile>(sortBy: [SortDescriptor(\Profile.name, order: .forward)])
        return try modelContext.fetch(descriptor)
    }

    func activeProfile(settings: AppSettings?) throws -> Profile? {
        if let activeID = settings?.activeProfileID {
            let descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == activeID })
            if let exact = try modelContext.fetch(descriptor).first {
                return exact
            }
        }

        let defaults = try modelContext.fetch(FetchDescriptor<Profile>(predicate: #Predicate { $0.isDefault == true }))
        if let defaultProfile = defaults.first {
            return defaultProfile
        }

        return try fetchProfiles().first
    }

    func timerConfig(for profileID: UUID) throws -> TimerConfig {
        let descriptor = FetchDescriptor<TimerConfig>(predicate: #Predicate { $0.profileID == profileID })
        if let config = try modelContext.fetch(descriptor).first {
            return config
        }

        let created = TimerConfig(profileID: profileID)
        modelContext.insert(created)
        try modelContext.save()
        return created
    }

    func websiteRules(for profileID: UUID) throws -> [WebsiteRule] {
        let descriptor = FetchDescriptor<WebsiteRule>(predicate: #Predicate { $0.profileID == profileID })
        return try modelContext.fetch(descriptor)
    }

    func appRules(for profileID: UUID) throws -> [BlockedAppRule] {
        let descriptor = FetchDescriptor<BlockedAppRule>(predicate: #Predicate { $0.profileID == profileID })
        return try modelContext.fetch(descriptor)
    }

    func scheduleRules(for profileID: UUID) throws -> [ScheduleRule] {
        let descriptor = FetchDescriptor<ScheduleRule>(predicate: #Predicate { $0.profileID == profileID && $0.isEnabled == true })
        return try modelContext.fetch(descriptor)
    }
}
