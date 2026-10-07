import AppKit
import SwiftUI

@main
struct WorkNrelaxApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("workNrelax", systemImage: coordinator.isPaused ? "pause.circle" : "laptopcomputer") {
            Button("Settings...") {
                coordinator.showSettings()
            }
            Divider()
            Button(coordinator.isPaused ? "Resume Reminders" : "Pause Reminders") {
                coordinator.togglePause()
            }
            Divider()
            Button("Quit workNrelax") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
        .environment(coordinator)
    }
}
