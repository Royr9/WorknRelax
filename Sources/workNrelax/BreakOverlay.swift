import AppKit
import SwiftUI

@MainActor
final class BreakOverlayController {
    private var window: NSWindow?

    func present(activeBreak: ActiveBreak, coordinator: AppCoordinator) {
        let overlayView = BreakOverlayView(activeBreak: activeBreak, coordinator: coordinator)
        let hostingController = NSHostingController(rootView: overlayView)

        if let window {
            window.contentViewController = hostingController
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.borderless, .fullSizeContentView]
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.setFrame(NSScreen.main?.frame ?? .zero, display: true)
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
        self.window = window
    }

    func dismiss() {
        window?.close()
        window = nil
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
            Button("Dismiss") {
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
}
