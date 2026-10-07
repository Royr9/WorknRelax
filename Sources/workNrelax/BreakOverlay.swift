import AppKit
import SwiftUI

@MainActor
final class BreakOverlayController {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var screenChangeListener: NSObjectProtocol?
    private var activeBreak: ActiveBreak?
    private weak var coordinator: AppCoordinator?

    func present(activeBreak: ActiveBreak, coordinator: AppCoordinator) {
        self.activeBreak = activeBreak
        self.coordinator = coordinator
        installScreenChangeListener()
        rebuildWindows()
    }

    func dismiss() {
        activeBreak = nil
        coordinator = nil
        removeScreenChangeListener()
        windows.values.forEach { $0.close() }
        windows.removeAll()
    }

    private func rebuildWindows() {
        guard let activeBreak, let coordinator else { return }
        let screens = NSScreen.screens
        let currentDisplayIDs = Set(screens.compactMap(\.displayID))

        for (displayID, window) in windows where !currentDisplayIDs.contains(displayID) {
            window.close()
            windows.removeValue(forKey: displayID)
        }

        for screen in screens {
            guard let displayID = screen.displayID else { continue }
            if let window = windows[displayID] {
                window.setFrame(screen.frame, display: true)
                continue
            }
            let overlayView = BreakOverlayView(activeBreak: activeBreak, coordinator: coordinator)
            let window = NSWindow(contentViewController: NSHostingController(rootView: overlayView))
            window.styleMask = [.borderless, .fullSizeContentView]
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
            windows[displayID] = window
        }
    }

    private func installScreenChangeListener() {
        guard screenChangeListener == nil else { return }
        screenChangeListener = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindows() }
        }
    }

    private func removeScreenChangeListener() {
        if let screenChangeListener {
            NotificationCenter.default.removeObserver(screenChangeListener)
        }
        screenChangeListener = nil
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

struct BreakOverlayView: View {
    let activeBreak: ActiveBreak
    let coordinator: AppCoordinator
    @State private var now = Date.now

    private var remaining: TimeInterval {
        max(0, activeBreak.endDate.timeIntervalSince(now))
    }

    private var remainingText: String {
        let totalSeconds = Int(remaining.rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        VStack(spacing: 28) {
            Text("Time to step away")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(activeBreak.message)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 780)
            Text(remainingText)
                .font(.system(size: 84, weight: .medium, design: .monospaced))
                .monospacedDigit()
            Button(buttonTitle) {
                coordinator.dismissBreak()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
            if remaining <= 0 {
                coordinator.dismissBreak()
            }
        }
    }

    private var buttonTitle: String {
        guard let reminder = coordinator.reminders.first(where: { $0.id == activeBreak.reminderID }),
              reminder.snoozeEnabled else { return "Dismiss" }
        return "Snooze \(reminder.snoozeMinutes) min"
    }
}
