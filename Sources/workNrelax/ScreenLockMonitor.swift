import AppKit
import Foundation

@MainActor
final class ScreenLockMonitor {
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private let onLock: () -> Void
    private let onUnlock: (TimeInterval) -> Void
    private var lockDate: Date?

    init(onLock: @escaping () -> Void, onUnlock: @escaping (TimeInterval) -> Void) {
        self.onLock = onLock
        self.onUnlock = onUnlock
    }

    func start() {
        guard lockObserver == nil else { return }
        let center = DistributedNotificationCenter.default
        lockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleLock() }
        }
        unlockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleUnlock() }
        }
    }

    func stop() {
        let center = DistributedNotificationCenter.default
        if let lockObserver { center.removeObserver(lockObserver) }
        if let unlockObserver { center.removeObserver(unlockObserver) }
        lockObserver = nil
        unlockObserver = nil
    }

    func handleLock() {
        lockDate = .now
        onLock()
    }

    func handleUnlock() {
        guard let lockDate else { return }
        let lockedDuration = Date.now.timeIntervalSince(lockDate)
        self.lockDate = nil
        onUnlock(lockedDuration)
    }
}
