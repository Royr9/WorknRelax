import Foundation

enum Weekday: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

enum ReminderSchedule: Codable, Equatable, Sendable {
    case interval(minutes: Int)
    case fixedTime(hour: Int, minute: Int, weekdays: Set<Weekday>)
}

struct Reminder: Identifiable, Equatable, Sendable {
    let id: UUID
    var isEnabled: Bool
    var message: String
    var breakDuration: TimeInterval
    var snoozeEnabled: Bool
    var snoozeMinutes: Int
    var schedule: ReminderSchedule

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        message: String,
        breakDuration: TimeInterval,
        snoozeEnabled: Bool = false,
        snoozeMinutes: Int = 5,
        schedule: ReminderSchedule
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.message = message
        self.breakDuration = breakDuration
        self.snoozeEnabled = snoozeEnabled
        self.snoozeMinutes = max(1, snoozeMinutes)
        self.schedule = schedule
    }

    var snoozeDuration: TimeInterval { TimeInterval(snoozeMinutes) * 60 }
}

extension Reminder: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, message, breakDuration, snoozeEnabled, snoozeMinutes, schedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        message = try container.decode(String.self, forKey: .message)
        breakDuration = try container.decode(TimeInterval.self, forKey: .breakDuration)
        snoozeEnabled = try container.decodeIfPresent(Bool.self, forKey: .snoozeEnabled) ?? false
        snoozeMinutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 5
        schedule = try container.decode(ReminderSchedule.self, forKey: .schedule)
    }

    var summary: String {
        switch schedule {
        case let .interval(minutes):
            return "Every \(minutes) minute\(minutes == 1 ? "" : "s")"
        case let .fixedTime(hour, minute, weekdays):
            let time = String(format: "%02d:%02d", hour, minute)
            let days = Weekday.allCases.filter { weekdays.contains($0) }.map(\.shortName).joined(separator: ", ")
            return "\(time) on \(days)"
        }
    }
}

struct ActiveBreak: Codable, Equatable, Sendable {
    let reminderID: UUID
    let message: String
    let endDate: Date
}
