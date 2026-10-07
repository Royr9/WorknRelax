import Foundation

struct ReminderScheduler: Sendable {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func nextFireDate(for reminder: Reminder, after date: Date) -> Date? {
        guard reminder.isEnabled else { return nil }

        switch reminder.schedule {
        case let .interval(minutes):
            guard minutes > 0 else { return nil }
            return calendar.date(byAdding: .minute, value: minutes, to: date)
        case let .fixedTime(hour, minute, weekdays):
            guard (0...23).contains(hour), (0...59).contains(minute), !weekdays.isEmpty else { return nil }

            for dayOffset in 0...7 {
                guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
                let weekday = calendar.component(.weekday, from: candidateDay)
                guard let candidateWeekday = Weekday(rawValue: weekday), weekdays.contains(candidateWeekday) else { continue }
                guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: candidateDay), candidate > date else { continue }
                return candidate
            }
            return nil
        }
    }
}
