import Foundation
@testable import workNrelax

enum WorkNrelaxTestScenarios {
static func intervalReminderSchedulesFromReferenceDate() {
    let calendar = Calendar(identifier: .gregorian)
    let scheduler = ReminderScheduler(calendar: calendar)
    let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    let reminder = Reminder(message: "Move", breakDuration: 300, schedule: .interval(minutes: 45))

    assert(scheduler.nextFireDate(for: reminder, after: referenceDate) == referenceDate.addingTimeInterval(45 * 60))
}

static func fixedTimeReminderFindsNextSelectedWeekday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let scheduler = ReminderScheduler(calendar: calendar)
    let sundayAtNoon = calendar.date(from: DateComponents(year: 2024, month: 6, day: 2, hour: 12))!
    let reminder = Reminder(message: "Lunch", breakDuration: 900, schedule: .fixedTime(hour: 12, minute: 30, weekdays: [.monday]))
    let expectedDate = calendar.date(from: DateComponents(year: 2024, month: 6, day: 3, hour: 12, minute: 30))!

    assert(scheduler.nextFireDate(for: reminder, after: sundayAtNoon) == expectedDate)
}

static func disabledReminderDoesNotSchedule() {
    let scheduler = ReminderScheduler()
    let reminder = Reminder(isEnabled: false, message: "Move", breakDuration: 300, schedule: .interval(minutes: 45))

    assert(scheduler.nextFireDate(for: reminder, after: .now) == nil)
}

static func reminderStoreRoundTripsValues() {
    let suiteName = "workNrelaxTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let store = ReminderStore(defaults: defaults)
    let reminder = Reminder(message: "Pushups", breakDuration: 120, schedule: .interval(minutes: 30))
    let activeBreak = ActiveBreak(reminderID: reminder.id, message: reminder.message, endDate: .now.addingTimeInterval(120))

    store.saveReminders([reminder])
    store.saveActiveBreak(activeBreak)

    assert(store.loadReminders() == [reminder])
    assert(store.loadActiveBreak() == activeBreak)
    store.clearActiveBreak()
    assert(store.loadActiveBreak() == nil)
    defaults.removePersistentDomain(forName: suiteName)
}

static func remainingBreakTimeUsesAbsoluteEndDate() async {
    let suiteName = "workNrelaxTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let store = ReminderStore(defaults: defaults)
    let coordinator = await MainActor.run { AppCoordinator(store: store) }
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let activeBreak = ActiveBreak(reminderID: UUID(), message: "Rest", endDate: now.addingTimeInterval(90))

    await MainActor.run {
        coordinator.activeBreak = activeBreak
        assert(coordinator.remainingBreakTime(at: now) == 90)
        assert(coordinator.remainingBreakTime(at: now.addingTimeInterval(120)) == 0)
    }
    defaults.removePersistentDomain(forName: suiteName)
}
}
