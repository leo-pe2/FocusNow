import SwiftData

enum FocusNowModelContainer {
    static func make() -> ModelContainer {
        let schema = Schema([
            Profile.self,
            TimerConfig.self,
            WebsiteRule.self,
            BlockedAppRule.self,
            ScheduleRule.self,
            SessionRecord.self,
            AppSettings.self
        ])

        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }
    }
}
