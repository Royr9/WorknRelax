workNrelax MVP Implementation Plan

## Overview

Build workNrelax as a personal, native macOS SwiftUI menu-bar app. It will schedule repeating and fixed-time reminders, display a dismissible full-screen break overlay, and keep break timing accurate across lock and sleep.

## Current State Analysis

This is a new application at `/Users/roy.ramati/Private/Dev-roy/workNrelax`; no implementation exists yet.

The MVP is intentionally macOS-only, local-only, and has no account, backend, sync, notifications-only mode, or distribution requirement. Native SwiftUI is the chosen approach because it provides menu-bar UI, AppKit window control, lifecycle events, and local persistence without an Electron runtime.

## Desired End State

workNrelax launches as a menu-bar application and provides a Settings window where the user can manage enabled reminders. Each reminder has a custom message and break duration, and is either a repeating interval or a fixed time with selected weekdays.

When a reminder fires, the app persists the active break end timestamp and presents a full-screen overlay. The overlay shows the message, a countdown based on wall-clock time, and a Dismiss action that can end the break early. After macOS wakes or the user unlocks the Mac, the app recalculates the remaining time from the persisted timestamp rather than trusting any paused in-memory timer.

### Key Discoveries
- The target is a new standalone project, so there are no existing app files, code conventions, or test setup to preserve.
- The previously inspected Electron and Raycast projects are deliberately out of scope; the app will use native SwiftUI and AppKit only.
- The selected behavior permits early dismissal, so the overlay must support both countdown completion and a user-initiated completion path.
- The active-break state must persist an absolute end date, not elapsed timer ticks, because macOS pauses timer delivery while asleep.

## What We're NOT Doing

- Raycast extension or Electron implementation.
- Backend, account, cloud sync, analytics, or network requests.
- Snooze, enforced breaks, blocking dismissal, or custom dismissal delays.
- Per-day date exceptions, reminder categories, history, reporting, or multiple display styles.
- App Store submission, code signing, auto-updates, or release automation.
- iPhone, iPad, Windows, or web support.

## Implementation Approach

Use a SwiftUI `MenuBarExtra` app as the process entry point, with a small AppKit bridge only where SwiftUI does not expose sufficient window behavior. Keep app state in observable model objects supplied by a single app coordinator.

Persist reminders and the optional active break as Codable data in `UserDefaults`. The scheduler calculates the next fire date for each enabled reminder and maintains only the needed timers. It re-evaluates all schedules after reminder changes, app activation, and macOS wake. The overlay counts down from the persisted absolute end date, which makes its state correct after sleep, locking, or a process restart.

---

## Phase 1: App Foundation And Persistent Models

### Overview

Create the native macOS SwiftUI project and establish the data model, persistence boundary, and application coordinator needed by every feature.

### Changes Required

#### 1. Xcode Project And Application Entry Point
- **File:** `workNrelax.xcodeproj/project.pbxproj`
- **Changes:** Create a macOS SwiftUI application target with the minimum supported macOS version selected during implementation.

- **File:** `workNrelaxApp.swift`
- **Changes:** Define the `@main` application, configure it as a menu-bar app, inject the app coordinator, and open Settings from the menu bar.

#### 2. Reminder And Break Models
- **File:** `Models/Reminder.swift`
- **Changes:** Add Codable, Identifiable reminder types.
- **Changes:** Model a reminder's identifier, enabled state, message, break duration, and one scheduling mode.
- **Changes:** Model interval scheduling in minutes and fixed-time scheduling as local clock time plus selected weekdays.

    Example model shape:

        enum ReminderSchedule: Codable {
            case interval(minutes: Int)
            case fixedTime(hour: Int, minute: Int, weekdays: Set<Weekday>)
        }

        struct Reminder: Codable, Identifiable {
            let id: UUID
            var isEnabled: Bool
            var message: String
            var breakDuration: TimeInterval
            var schedule: ReminderSchedule
        }

- **File:** `Models/ActiveBreak.swift`
- **Changes:** Add a Codable active-break record containing the source reminder ID, displayed message, and absolute end date.

#### 3. Local Persistence
- **File:** `Services/ReminderStore.swift`
- **Changes:** Load and save the reminder collection in `UserDefaults` using `JSONEncoder` and `JSONDecoder`.
- **Changes:** Load, save, and clear the optional active-break record separately.
- **Changes:** Treat corrupted or unavailable stored data as empty state; do not crash the menu-bar process.

#### 4. App Coordinator
- **File:** `Services/AppCoordinator.swift`
- **Changes:** Own reminders, app-wide pause state, active break state, persistence calls, and hooks that later phases use for scheduler and overlay actions.
- **Changes:** Restore an active break during launch only when its persisted end date is still in the future; otherwise clear stale state.

### Success Criteria

**Automated Verification:**
- [ ] The macOS target builds from Xcode or `xcodebuild`.
- [ ] Unit tests verify reminder and active-break Codable round trips.
- [ ] Unit tests verify missing or corrupt persisted values fall back safely.

**Manual Verification:**
- [ ] Launching displays a menu-bar item without requiring an app account or network access.
- [ ] A relaunch restores saved reminder data.

> **Implementation Note:** After completing this phase and automated verification passes, pause for manual confirmation before proceeding to the next phase.

---

## Phase 2: Reminder Scheduling

### Overview

Implement deterministic next-fire-date calculation and connect it to the enabled reminder collection.

### Changes Required

#### 1. Next-Fire-Date Calculation
- **File:** `Services/ReminderScheduler.swift`
- **Changes:** Add pure scheduling functions that accept a reminder and a reference date, then return the next eligible fire date in the user's current macOS calendar and time zone.
- **Changes:** For interval reminders, schedule the next occurrence from the previous scheduling/firing reference used by the coordinator, avoiding multiple immediate firings after a late wake.
- **Changes:** For fixed-time reminders, find the next selected weekday at the configured local hour and minute, including the same day only when its time has not passed.
- **Changes:** Reject invalid values in the UI layer and defensively ignore invalid persisted schedules.

#### 2. Runtime Timer Management
- **File:** `Services/ReminderScheduler.swift`
- **Changes:** Maintain a timer for the earliest due enabled reminder and reschedule after a reminder is added, edited, removed, enabled, disabled, paused, fired, or dismissed.
- **Changes:** When a reminder is due, notify the app coordinator with its reminder ID rather than presenting UI directly.
- **Changes:** Skip new break launches while a break is already active; reschedule normally after it ends.

#### 3. Sleep And Wake Reconciliation
- **File:** `workNrelaxApp.swift`
- **Changes:** Observe macOS wake and active-state notifications and request coordinator reconciliation.

- **File:** `Services/AppCoordinator.swift`
- **Changes:** Reconcile the active break using current wall-clock time and rebuild scheduler timers after wake or app reactivation.

### Success Criteria

**Automated Verification:**
- [ ] Unit tests cover interval next-fire calculation.
- [ ] Unit tests cover fixed-time scheduling for today, a later selected weekday, and rollover to the following week.
- [ ] Unit tests confirm disabled and paused reminders do not produce a scheduled fire date.
- [ ] The macOS target builds successfully.

**Manual Verification:**
- [ ] An enabled short interval reminder fires once and schedules its following occurrence.
- [ ] A fixed-time reminder fires only on its selected weekdays.
- [ ] Pausing prevents upcoming reminders and resuming re-establishes schedules.

> **Implementation Note:** After completing this phase and automated verification passes, pause for manual confirmation before proceeding to the next phase.

---

## Phase 3: Settings And Menu-Bar Controls

### Overview

Provide the minimal settings experience needed to manage all reminder fields and control the app from the menu bar.

### Changes Required

#### 1. Settings Window
- **File:** `Views/SettingsView.swift`
- **Changes:** Show existing reminders in a list with enabled state, summary, edit action, and delete action.
- **Changes:** Provide an empty state and an Add Reminder action.

- **File:** `Views/ReminderEditorView.swift`
- **Changes:** Provide a form to create or edit a reminder.
- **Changes:** Include scheduling mode selection, interval value or local time and weekday controls, message, break duration, and enabled state.
- **Changes:** Validate non-empty messages, positive interval values, positive break durations, and at least one selected weekday for fixed-time reminders.
- **Changes:** Save only valid reminders through the coordinator, which persists changes and updates schedules.

#### 2. Menu-Bar Menu
- **File:** `workNrelaxApp.swift`
- **Changes:** Add actions for Open Settings, Pause Reminders/Resume Reminders, and Quit.
- **Changes:** Reflect the active paused state in the menu label.

### Success Criteria

**Automated Verification:**
- [ ] Unit tests cover validation for each reminder type.
- [ ] Unit tests cover add, update, delete, enable, and disable persistence through the coordinator/store boundary.
- [ ] The macOS target builds successfully.

**Manual Verification:**
- [ ] A user can add, edit, disable, and delete both reminder types from Settings.
- [ ] Invalid form entries cannot be saved and explain what must be corrected.
- [ ] Menu-bar Pause Reminders takes effect immediately and survives only for the running session unless deliberately persisted in implementation.

> **Implementation Note:** After completing this phase and automated verification passes, pause for manual confirmation before proceeding to the next phase.

---

## Phase 4: Full-Screen Break Overlay

### Overview

Show reminders as a focused full-screen break experience and maintain its real-world countdown correctly across sleep and lock.

### Changes Required

#### 1. Overlay Window Controller
- **File:** `Services/BreakOverlayController.swift`
- **Changes:** Create and manage a dedicated borderless AppKit window above normal application windows.
- **Changes:** Present it in full-screen mode when a break begins and close it when the break ends or is dismissed.
- **Changes:** Keep the overlay independent of the Settings window so Settings can remain closed while the reminder app runs.

#### 2. Overlay View
- **File:** `Views/BreakOverlayView.swift`
- **Changes:** Display the active reminder message, a countdown derived from `endDate - Date()`, and a Dismiss button.
- **Changes:** Update the presentation on a lightweight periodic refresh, but derive each displayed value from the absolute end date.
- **Changes:** On Dismiss, request the coordinator to clear persisted active-break state, close the overlay, and resume normal scheduling.
- **Changes:** When the remaining duration reaches zero, clear active-break state and close the overlay automatically.

#### 3. Active-Break Lifecycle
- **File:** `Services/AppCoordinator.swift`
- **Changes:** On scheduler fire, persist the active break before presenting the overlay.
- **Changes:** On app launch, wake, or unlock/activation, restore the overlay if an active break remains; otherwise clear stale state.
- **Changes:** Ensure early dismissal clears the active state so it does not reappear after a subsequent lock or app restart.

### Success Criteria

**Automated Verification:**
- [ ] Unit tests verify active-break remaining time uses end date minus the supplied current date.
- [ ] Unit tests verify a completed or dismissed break is cleared and not restored.
- [ ] The macOS target builds successfully.

**Manual Verification:**
- [ ] A triggered reminder opens a full-screen overlay with its own message and duration.
- [ ] The countdown ends automatically at the configured break duration.
- [ ] Dismiss closes the overlay before the timer finishes and it does not reopen.
- [ ] Locking the Mac or closing its lid during an active break does not pause elapsed time; after unlock/wake, the overlay shows the correct remaining time or has completed.

> **Implementation Note:** After completing this phase and automated verification passes, pause for manual confirmation before proceeding to the next phase.

---

## Phase 5: MVP Validation And Developer Documentation

### Overview

Ensure the project can be built locally and document its intentionally narrow personal-use workflow.

### Changes Required

#### 1. Project Documentation
- **File:** `README.md`
- **Changes:** Document prerequisites, how to open and run the Xcode project, how to configure each reminder type, and the expected sleep/lock behavior.
- **Changes:** State the MVP limitations: local-only data, no snooze, and early dismissal.

#### 2. Test And Build Configuration
- **File:** `workNrelaxTests/`
- **Changes:** Organize unit tests for models, persistence, scheduling, and active-break time calculations.
- **Changes:** Add the test target to the Xcode project.

### Success Criteria

**Automated Verification:**
- [ ] `xcodebuild test` passes for the configured macOS scheme and destination.
- [ ] `xcodebuild build` completes without errors for the configured macOS scheme.
- [ ] `README.md` describes the actual local development and MVP behavior.

**Manual Verification:**
- [ ] A fresh launch with no data provides a clear path to create the first reminder.
- [ ] Repeating and fixed-time reminders work in the same running session.
- [ ] Settings, pause/resume, full-screen overlay, dismissal, relaunch recovery, and sleep/lock recovery all work on macOS.

> **Implementation Note:** After completing this phase and automated verification passes, pause for manual confirmation before considering the MVP complete.

---

## Testing Strategy

### Unit Tests
- Codable round trips and safe defaults for reminder and active-break persistence.
- Reminder store reads, writes, deletes, and corrupt-data recovery.
- Interval schedule calculation and fixed-time weekday selection around day and week boundaries.
- Validation for empty messages, non-positive durations and intervals, and missing fixed-time weekdays.
- Active-break completion and remaining-time calculations with injected reference dates.

### Integration Tests
- Coordinator schedules enabled reminders and ignores disabled or paused reminders.
- Editing or deleting a reminder rebuilds the scheduler without leaving duplicate scheduled fires.
- A fired reminder persists the break before presentation and a dismissal clears it.
- Relaunch/wake reconciliation restores only breaks whose end date is still in the future.
