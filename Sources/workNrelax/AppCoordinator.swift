import AppKit
import Foundation
import Observation

@MainActor @Observable
final class AppCoordinator {
    var reminders: [Reminder]
    var isPaused = false
    var activeBreak: ActiveBreak?
    private(set) var nextFireDates: [UUID: Date] = [:]

    private let store: ReminderStore
    private let scheduler: ReminderScheduler
    private let overlayController = BreakOverlayController()
    private let settingsWindowController = SettingsWindowController()
    private var scheduledTimers: [UUID: Timer] = [:]
    private var wakeObserver: NSObjectProtocol?

    init(store: ReminderStore = ReminderStore(), scheduler: ReminderScheduler = ReminderScheduler()) {
        self.store = store
        self.scheduler = scheduler
        reminders = store.loadReminders()
        activeBreak = store.loadActiveBreak()
        start()
    }

    func start() {
        guard wakeObserver == nil else { return }
        reconcileActiveBreak()
        scheduleReminders()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileAfterWake() }
        }
    }

    func stop() {
        scheduledTimers.values.forEach { $0.invalidate() }
        scheduledTimers.removeAll()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func saveReminder(_ reminder: Reminder) {
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index] = reminder
        } else {
            reminders.append(reminder)
        }
        store.saveReminders(reminders)
        scheduleReminders()
    }

    func deleteReminder(id: UUID) {
        reminders.removeAll { $0.id == id }
        store.saveReminders(reminders)
        scheduleReminders()
    }

    func togglePause() {
        isPaused.toggle()
        scheduleReminders()
    }

    func showSettings() {
        settingsWindowController.present(coordinator: self)
    }

    func dismissBreak() {
        activeBreak = nil
        store.clearActiveBreak()
        overlayController.dismiss()
        scheduleReminders()
    }

    func remainingBreakTime(at date: Date = .now) -> TimeInterval {
        guard let activeBreak else { return 0 }
        return max(0, activeBreak.endDate.timeIntervalSince(date))
    }

    func remainingTimeUntilReminder(id: UUID, at date: Date = .now) -> TimeInterval? {
        guard let fireDate = nextFireDates[id] else { return nil }
        return max(0, fireDate.timeIntervalSince(date))
    }

    func reconcileActiveBreak() {
        guard let activeBreak else { return }
        guard remainingBreakTime() > 0 else {
            dismissBreak()
            return
        }
        overlayController.present(activeBreak: activeBreak, coordinator: self)
    }

    private func reconcileAfterWake() {
        reconcileActiveBreak()
        scheduleReminders()
    }

    private func scheduleReminders() {
        scheduledTimers.values.forEach { $0.invalidate() }
        scheduledTimers.removeAll()
        nextFireDates.removeAll()
        guard !isPaused, activeBreak == nil else { return }

        let now = Date.now
        for reminder in reminders {
            guard let fireDate = scheduler.nextFireDate(for: reminder, after: now) else { continue }
            let timer = Timer(fireAt: fireDate, interval: 0, target: TimerTarget { [weak self] in
                self?.fire(reminder)
            }, selector: #selector(TimerTarget.execute), userInfo: nil, repeats: false)
            RunLoop.main.add(timer, forMode: .common)
            scheduledTimers[reminder.id] = timer
            nextFireDates[reminder.id] = fireDate
        }
    }

    private func fire(_ reminder: Reminder) {
        scheduledTimers[reminder.id]?.invalidate()
        scheduledTimers.removeValue(forKey: reminder.id)
        nextFireDates.removeValue(forKey: reminder.id)
        guard activeBreak == nil, reminder.isEnabled, !isPaused else {
            scheduleReminders()
            return
        }

        let activeBreak = ActiveBreak(
            reminderID: reminder.id,
            message: reminder.message,
            endDate: Date.now.addingTimeInterval(reminder.breakDuration)
        )
        self.activeBreak = activeBreak
        store.saveActiveBreak(activeBreak)
        overlayController.present(activeBreak: activeBreak, coordinator: self)
    }
}

private final class TimerTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func execute() {
        action()
    }
}
