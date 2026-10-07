import Foundation

enum LockCredit {
    /// Next fire date after unlock, crediting locked time as rest.
    /// Locked >= full break duration = timer reset (fresh interval).
    /// Partial lock adds a proportional bonus (locked/breakDuration x interval) on top
    /// of the fresh interval, since the reminder clock was paused while locked.
    static func nextFireDate(
        unlockedAt: Date,
        lockedDuration: TimeInterval,
        reminder: Reminder
    ) -> Date? {
        guard reminder.isEnabled else { return nil }
        switch reminder.schedule {
        case let .interval(minutes):
            guard minutes > 0 else { return nil }
            let interval = TimeInterval(minutes) * 60
            guard lockedDuration < reminder.breakDuration, reminder.breakDuration > 0 else {
                return unlockedAt.addingTimeInterval(interval)
            }
            let bonus = (lockedDuration / reminder.breakDuration) * interval
            return unlockedAt.addingTimeInterval(interval + bonus)
        case .fixedTime:
            // Clock-anchored schedules have no "time until next" to credit.
            return nil
        }
    }
}
