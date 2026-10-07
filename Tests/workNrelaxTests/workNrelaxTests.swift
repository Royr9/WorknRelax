import Foundation
import Testing
@testable import workNrelax

@Suite("WorkNrelax")
struct WorkNrelaxTests {

    @Test func intervalReminderSchedulesFromReferenceDate() {
        let calendar = Calendar(identifier: .gregorian)
        let scheduler = ReminderScheduler(calendar: calendar)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let reminder = Reminder(message: "Move", breakDuration: 300, schedule: .interval(minutes: 45))

        #expect(scheduler.nextFireDate(for: reminder, after: referenceDate) == referenceDate.addingTimeInterval(45 * 60))
    }

    @Test func fixedTimeReminderFindsNextSelectedWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let scheduler = ReminderScheduler(calendar: calendar)
        let sundayAtNoon = calendar.date(from: DateComponents(year: 2024, month: 6, day: 2, hour: 12))!
        let reminder = Reminder(message: "Lunch", breakDuration: 900, schedule: .fixedTime(hour: 12, minute: 30, weekdays: [.monday]))
        let expectedDate = calendar.date(from: DateComponents(year: 2024, month: 6, day: 3, hour: 12, minute: 30))!

        #expect(scheduler.nextFireDate(for: reminder, after: sundayAtNoon) == expectedDate)
    }

    @Test func disabledReminderDoesNotSchedule() {
        let scheduler = ReminderScheduler()
        let reminder = Reminder(isEnabled: false, message: "Move", breakDuration: 300, schedule: .interval(minutes: 45))

        #expect(scheduler.nextFireDate(for: reminder, after: .now) == nil)
    }

    @Test func reminderStoreRoundTripsValues() {
        let suiteName = "workNrelaxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ReminderStore(defaults: defaults)
        let reminder = Reminder(message: "Pushups", breakDuration: 120, schedule: .interval(minutes: 30))
        let activeBreak = ActiveBreak(reminderID: reminder.id, message: reminder.message, endDate: .now.addingTimeInterval(120))

        store.saveReminders([reminder])
        store.saveActiveBreak(activeBreak)

        #expect(store.loadReminders() == [reminder])
        #expect(store.loadActiveBreak() == activeBreak)
        store.clearActiveBreak()
        #expect(store.loadActiveBreak() == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func remainingBreakTimeUsesAbsoluteEndDate() async {
        let suiteName = "workNrelaxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ReminderStore(defaults: defaults)
        let coordinator = await MainActor.run { AppCoordinator(store: store) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let activeBreak = ActiveBreak(reminderID: UUID(), message: "Rest", endDate: now.addingTimeInterval(90))

        await MainActor.run {
            coordinator.activeBreak = activeBreak
            #expect(coordinator.remainingBreakTime(at: now) == 90)
            #expect(coordinator.remainingBreakTime(at: now.addingTimeInterval(120)) == 0)
        }
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func legacyReminderPayloadDecodesWithoutSnooze() throws {
        let legacyJSON = """
        {"id":"5ECF3E0C-4A13-4E28-9A57-6D9F5E9B1A22","isEnabled":true,"message":"Move","breakDuration":300,"schedule":{"interval":{"minutes":45}}}
        """
        let reminder = try JSONDecoder().decode(Reminder.self, from: Data(legacyJSON.utf8))

        #expect(reminder.snoozeEnabled == false)
        #expect(reminder.message == "Move")
    }

    @Test func snoozedReminderRoundTripsThroughStore() {
        let suiteName = "workNrelaxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ReminderStore(defaults: defaults)
        let reminder = Reminder(message: "Stretch", breakDuration: 300, snoozeEnabled: true, snoozeMinutes: 10, schedule: .interval(minutes: 30))

        store.saveReminders([reminder])

        let loaded = store.loadReminders().first
        #expect(loaded?.snoozeEnabled == true)
        #expect(loaded?.snoozeMinutes == 10)
        #expect(loaded?.snoozeDuration == 600)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func legacySnoozeDefaultsToFiveMinutes() throws {
        let legacyJSON = """
        {"id":"5ECF3E0C-4A13-4E28-9A57-6D9F5E9B1A22","isEnabled":true,"message":"Move","breakDuration":300,"snoozeEnabled":true,"schedule":{"interval":{"minutes":45}}}
        """
        let reminder = try JSONDecoder().decode(Reminder.self, from: Data(legacyJSON.utf8))

        #expect(reminder.snoozeEnabled == true)
        #expect(reminder.snoozeMinutes == 5)
    }

    @Test func lockCreditFullResetWhenLockedLongEnough() {
        let reminder = Reminder(message: "Move", breakDuration: 600, schedule: .interval(minutes: 45))
        let unlockedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let fireDate = LockCredit.nextFireDate(
            unlockedAt: unlockedAt,
            lockedDuration: 700,
            reminder: reminder
        )

        #expect(fireDate == unlockedAt.addingTimeInterval(45 * 60))
    }

    @Test func lockCreditPartialGivesProportionalExtraTime() {
        // break 600s, interval 2700s; locked 60s -> fraction 0.1 -> bonus 270s on top of fresh interval
        let reminder = Reminder(message: "Move", breakDuration: 600, schedule: .interval(minutes: 45))
        let unlockedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let fireDate = LockCredit.nextFireDate(
            unlockedAt: unlockedAt,
            lockedDuration: 60,
            reminder: reminder
        )

        #expect(fireDate == unlockedAt.addingTimeInterval(45 * 60 + 270))
    }

    @Test func lockCreditZeroGivesPlainInterval() {
        let reminder = Reminder(message: "Move", breakDuration: 600, schedule: .interval(minutes: 45))
        let unlockedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let fireDate = LockCredit.nextFireDate(
            unlockedAt: unlockedAt,
            lockedDuration: 0,
            reminder: reminder
        )

        #expect(fireDate == unlockedAt.addingTimeInterval(45 * 60))
    }

    @Test func lockCreditIgnoresFixedTimeReminders() {
        let reminder = Reminder(message: "Lunch", breakDuration: 600, schedule: .fixedTime(hour: 12, minute: 30, weekdays: [.monday]))

        let fireDate = LockCredit.nextFireDate(
            unlockedAt: .now,
            lockedDuration: 300,
            reminder: reminder
        )

        #expect(fireDate == nil)
    }
}
