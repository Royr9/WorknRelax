import Foundation

final class ReminderStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let remindersKey = "reminders"
    private let activeBreakKey = "activeBreak"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadReminders() -> [Reminder] {
        decode([Reminder].self, forKey: remindersKey) ?? []
    }

    func saveReminders(_ reminders: [Reminder]) {
        save(reminders, forKey: remindersKey)
    }

    func loadActiveBreak() -> ActiveBreak? {
        decode(ActiveBreak.self, forKey: activeBreakKey)
    }

    func saveActiveBreak(_ activeBreak: ActiveBreak) {
        save(activeBreak, forKey: activeBreakKey)
    }

    func clearActiveBreak() {
        defaults.removeObject(forKey: activeBreakKey)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
