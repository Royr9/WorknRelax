import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var editingReminder: Reminder?
    @State private var isAddingReminder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Reminders").font(.title2.bold())
                Spacer()
                Button("Add Reminder") { isAddingReminder = true }
            }

            if coordinator.reminders.isEmpty {
                ContentUnavailableView("No reminders", systemImage: "clock", description: Text("Add a reminder to start building healthier breaks."))
            } else {
                List {
                    ForEach(coordinator.reminders) { reminder in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { reminder.isEnabled },
                                set: { enabled in
                                    var updated = reminder
                                    updated.isEnabled = enabled
                                    coordinator.saveReminder(updated)
                                }
                            ))
                            .labelsHidden()
                            VStack(alignment: .leading) {
                                Text(reminder.message).fontWeight(.medium)
                                Text("\(reminder.summary) | \(Int(reminder.breakDuration / 60)) min break")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if case .interval = reminder.schedule, reminder.isEnabled {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        if let remaining = coordinator.remainingTimeUntilReminder(id: reminder.id, at: context.date) {
                                            Text("Next break in \(countdownText(remaining))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                        }
                                    }
                                }
                            }
                            Spacer()
                            Button("Edit") { editingReminder = reminder }
                            Button("Delete", role: .destructive) { coordinator.deleteReminder(id: reminder.id) }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 400)
        .sheet(isPresented: $isAddingReminder) {
            ReminderEditorView { coordinator.saveReminder($0) }
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditorView(reminder: reminder) { coordinator.saveReminder($0) }
        }
    }

    private func countdownText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let existingReminder: Reminder?
    let onSave: (Reminder) -> Void
    @State private var isEnabled: Bool
    @State private var message: String
    @State private var breakMinutes: Int
    @State private var scheduleKind: ScheduleKind
    @State private var intervalMinutes: Int
    @State private var fixedHour: Int
    @State private var fixedMinute: Int
    @State private var weekdays: Set<Weekday>

    enum ScheduleKind: String, CaseIterable, Identifiable {
        case interval = "Repeating interval"
        case fixedTime = "Fixed time"
        var id: String { rawValue }
    }

    init(reminder: Reminder? = nil, onSave: @escaping (Reminder) -> Void) {
        existingReminder = reminder
        self.onSave = onSave
        _isEnabled = State(initialValue: reminder?.isEnabled ?? true)
        _message = State(initialValue: reminder?.message ?? "Take a break")
        _breakMinutes = State(initialValue: Int((reminder?.breakDuration ?? 300) / 60))
        if case let .fixedTime(hour, minute, weekdays) = reminder?.schedule {
            _scheduleKind = State(initialValue: .fixedTime)
            _fixedHour = State(initialValue: hour)
            _fixedMinute = State(initialValue: minute)
            _weekdays = State(initialValue: weekdays)
        } else {
            _scheduleKind = State(initialValue: .interval)
            let components = Calendar.current.dateComponents([.hour, .minute], from: .now)
            _fixedHour = State(initialValue: components.hour ?? 9)
            _fixedMinute = State(initialValue: components.minute ?? 0)
            _weekdays = State(initialValue: [.monday, .tuesday, .wednesday, .thursday, .friday])
        }
        if case let .interval(minutes) = reminder?.schedule {
            _intervalMinutes = State(initialValue: minutes)
        } else {
            _intervalMinutes = State(initialValue: 45)
        }
    }

    private var isValid: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && breakMinutes > 0
            && (scheduleKind == .interval ? intervalMinutes > 0 : !weekdays.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingReminder == nil ? "Add Reminder" : "Edit Reminder").font(.title2.bold())
            Toggle("Enabled", isOn: $isEnabled)
            LabeledContent("Message") {
                TextField("Take a break", text: $message)
                    .textFieldStyle(.roundedBorder)
            }
            numberInput(label: "Break duration", value: $breakMinutes, range: 1...180, suffix: "minutes")
            VStack(alignment: .leading, spacing: 10) {
                Text("Schedule").fontWeight(.medium)
                Picker("Schedule", selection: $scheduleKind) {
                    ForEach(ScheduleKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if scheduleKind == .interval {
                    numberInput(label: "Repeat every", value: $intervalMinutes, range: 1...720, suffix: "minutes")
                } else {
                    LabeledContent("Time") {
                        HStack(spacing: 6) {
                            numericField(value: $fixedHour, range: 0...23)
                            Text(":").font(.title3.monospacedDigit())
                            numericField(value: $fixedMinute, range: 0...59)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Weekday.allCases) { weekday in
                            Toggle(weekday.shortName, isOn: Binding(
                                get: { weekdays.contains(weekday) },
                                set: { selected in
                                    if selected { weekdays.insert(weekday) } else { weekdays.remove(weekday) }
                                }
                            ))
                            .toggleStyle(.button)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent).disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func save() {
        let schedule: ReminderSchedule
        if scheduleKind == .interval {
            schedule = .interval(minutes: intervalMinutes)
        } else {
            schedule = .fixedTime(hour: fixedHour, minute: fixedMinute, weekdays: weekdays)
        }
        onSave(Reminder(
            id: existingReminder?.id ?? UUID(),
            isEnabled: isEnabled,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            breakDuration: TimeInterval(breakMinutes * 60),
            schedule: schedule
        ))
        dismiss()
    }

    private func numberInput(label: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
            Stepper("", value: value, in: range)
                .labelsHidden()
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }

    private func numericField(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
    }
}
