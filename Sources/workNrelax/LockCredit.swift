import Foundation

enum LockCredit {
    /// Locks shorter than this earn no credit — the schedule is left untouched.
    static let minimumLockDuration: TimeInterval = 120
    /// Bonus seconds added to the next-reminder wait per second locked.
    static let bonusRate: TimeInterval = 5

    /// Next fire date after unlock, crediting locked time as rest.
    /// A lock of at least `minimumLockDuration` extends the existing countdown by
    /// `lockedDuration x bonusRate`, capped so the wait never exceeds the repeat interval.
    static func nextFireDate(
        unlockedAt: Date,
        lockedDuration: TimeInterval,
        reminder: Reminder,
        currentFireDate: Date?
    ) -> Date? {
        guard reminder.isEnabled else { return nil }
        switch reminder.schedule {
        case let .interval(minutes):
            guard minutes > 0 else { return nil }
            let interval = TimeInterval(minutes) * 60
            guard lockedDuration > minimumLockDuration else { return nil }
            let bonus = lockedDuration * bonusRate
            let remaining = currentFireDate.map { max(0, $0.timeIntervalSince(unlockedAt)) } ?? 0
            return unlockedAt.addingTimeInterval(min(remaining + bonus, interval))
        case .fixedTime:
            // Clock-anchored schedules have no "time until next" to credit.
            return nil
        }
    }
}
