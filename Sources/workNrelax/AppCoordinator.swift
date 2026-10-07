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
    private var screenLockMonitor: ScreenLockMonitor?
    private var scheduledTimers: [UUID: Timer] = [:]
    private var wakeObserver: NSObjectProtocol?
    private var snoozeOverrides: [UUID: Date] = [:]
    private var isScreenLocked = false

    init(store: ReminderStore = ReminderStore(), scheduler: ReminderScheduler = ReminderScheduler()) {
        self.store = store
        self.scheduler = scheduler
        reminders = store.loadReminders()
        activeBreak = store.loadActiveBreak()
        start()
    }

    func start() {
        guard wakeObserver == nil else { return }
        if screenLockMonitor == nil {
            screenLockMonitor = ScreenLockMonitor(
                onLock: { [weak self] in self?.handleScreenLock() },
                onUnlock: { [weak self] duration in self?.handleScreenUnlock(lockedDuration: duration) }
            )
        }
        reconcileActiveBreak()
        scheduleReminders()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileAfterWake() }
        }
        screenLockMonitor?.start()
    }

    func stop() {
        scheduledTimers.values.forEach { $0.invalidate() }
        scheduledTimers.removeAll()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        screenLockMonitor?.stop()
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
        if let activeBreak, let snoozeDate = snoozeTarget(for: activeBreak) {
            snoozeOverrides[activeBreak.reminderID] = snoozeDate
        }
        activeBreak = nil
        store.clearActiveBreak()
        overlayController.dismiss()
        scheduleReminders()
    }

    func snoozeTarget(for activeBreak: ActiveBreak) -> Date? {
        guard let reminder = reminders.first(where: { $0.id == activeBreak.reminderID }),
              reminder.snoozeEnabled else { return nil }
        return Date.now.addingTimeInterval(reminder.snoozeDuration)
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
        guard !isScreenLocked else { return }
        reconcileActiveBreak()
        scheduleReminders()
    }

    private func handleScreenLock() {
        isScreenLocked = true
        scheduledTimers.values.forEach { $0.invalidate() }
        scheduledTimers.removeAll()
    }

    private func handleScreenUnlock(lockedDuration: TimeInterval) {
        isScreenLocked = false
        applyLockCredit(lockedDuration: lockedDuration)
        reconcileActiveBreak()
        scheduleReminders(preservingFireDates: true)
    }

    private func applyLockCredit(lockedDuration: TimeInterval) {
        let now = Date.now
        for reminder in reminders {
            guard case .interval = reminder.schedule,
                  reminder.isEnabled,
                  let creditFireDate = LockCredit.nextFireDate(
                    unlockedAt: now,
                    lockedDuration: lockedDuration,
                    reminder: reminder
                  ) else { continue }
            if let currentFireDate = nextFireDates[reminder.id], currentFireDate > now {
                nextFireDates[reminder.id] = max(currentFireDate, creditFireDate)
            } else {
                nextFireDates[reminder.id] = creditFireDate
            }
        }
    }

    private func scheduleReminders(preservingFireDates: Bool = false) {
        scheduledTimers.values.forEach { $0.invalidate() }
        scheduledTimers.removeAll()
        if !preservingFireDates {
            nextFireDates.removeAll()
        }
        guard !isPaused, activeBreak == nil, !isScreenLocked else { return }

        let now = Date.now
        for reminder in reminders {
            let fireDate: Date?
            if let snoozeDate = snoozeOverrides[reminder.id], snoozeDate > now {
                fireDate = snoozeDate
            } else if preservingFireDates, let existing = nextFireDates[reminder.id], existing > now {
                fireDate = existing
            } else {
                fireDate = scheduler.nextFireDate(for: reminder, after: now)
            }
            snoozeOverrides.removeValue(forKey: reminder.id)
            guard let fireDate else { continue }
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

private extension Reminder {
    var intervalMinutes: Int {
        if case let .interval(minutes) = schedule { return minutes }
        return 0
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
