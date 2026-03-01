import Foundation

@MainActor
final class ScheduleManager {
    private var timer: Timer?
    private(set) var nextTriggerDate: Date?

    func arm(
        rules: [ScheduleRule],
        now: Date = .now,
        onTrigger: @escaping () -> Void
    ) {
        timer?.invalidate()
        nextTriggerDate = nextTrigger(for: rules, now: now)

        guard let nextTriggerDate else { return }

        let interval = max(1, nextTriggerDate.timeIntervalSince(now))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            onTrigger()
        }
    }

    func recompute(
        rules: [ScheduleRule],
        now: Date = .now,
        onTrigger: @escaping () -> Void
    ) {
        arm(rules: rules, now: now, onTrigger: onTrigger)
    }

    func nextTrigger(for rules: [ScheduleRule], now: Date = .now) -> Date? {
        rules.compactMap { nextDate(for: $0, now: now) }.sorted().first
    }

    private func nextDate(for rule: ScheduleRule, now: Date) -> Date? {
        guard rule.isEnabled else { return nil }

        let timezone = TimeZone(identifier: rule.timezoneID) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }

            let weekday = calendar.component(.weekday, from: day)
            if !matches(recurrence: rule.recurrence, weekday: weekday, customWeekdays: rule.weekdayNumbers) {
                continue
            }

            let hour = max(0, min(23, rule.startTimeMinuteOfDay / 60))
            let minute = max(0, min(59, rule.startTimeMinuteOfDay % 60))

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let candidate = calendar.date(from: components) else { continue }
            if candidate > now {
                return candidate
            }
        }

        return nil
    }

    private func matches(recurrence: ScheduleRecurrence, weekday: Int, customWeekdays: [Int]) -> Bool {
        switch recurrence {
        case .daily:
            return true
        case .weekdays:
            return (2...6).contains(weekday)
        case .weekends:
            return weekday == 1 || weekday == 7
        case .customWeekdays:
            return customWeekdays.contains(weekday)
        }
    }
}
