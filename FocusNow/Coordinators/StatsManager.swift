import Foundation
import SwiftData

@MainActor
final class StatsManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func recordSession(summary: SessionSummary, profileID: UUID) {
        let record = SessionRecord(
            profileID: profileID,
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSeconds: summary.durationSeconds,
            completedPomodoros: summary.completedPomodoros,
            endedReason: summary.endedReason,
            lockedOverrideUsed: summary.lockedOverrideUsed
        )

        modelContext.insert(record)
        try? modelContext.save()
    }

    func totalFocusSeconds(from: Date, to: Date) -> Int {
        let predicate = #Predicate<SessionRecord> { record in
            record.startedAt >= from && record.endedAt <= to
        }

        let descriptor = FetchDescriptor<SessionRecord>(predicate: predicate)
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.reduce(0) { $0 + $1.durationSeconds }
    }

    func streakCount(today: Date = .now) -> Int {
        let descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\SessionRecord.startedAt, order: .reverse)])
        let records = (try? modelContext.fetch(descriptor)) ?? []
        guard !records.isEmpty else { return 0 }

        let calendar = Calendar.current
        var streak = 0
        var cursor = calendar.startOfDay(for: today)

        while true {
            guard let nextDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            let dayRecords = records.filter { calendar.isDate($0.startedAt, inSameDayAs: cursor) }
            if dayRecords.isEmpty {
                if streak == 0 {
                    cursor = nextDay
                    continue
                }
                break
            }

            streak += 1
            cursor = nextDay
        }

        return streak
    }
}
