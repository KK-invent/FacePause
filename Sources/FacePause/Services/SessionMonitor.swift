import AppKit
import CoreGraphics

@MainActor final class SessionMonitor {
    private var unavailableReasons = Set<String>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    var onUnavailable: (() -> Void)?
    var onResume: (() -> Void)?
    var available: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let onConsole = session?[kCGSessionOnConsoleKey as String] as? Bool ?? true
        return unavailableReasons.isEmpty && !locked && onConsole
    }
    init() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "sleep"),
                               (NSWorkspace.screensDidSleepNotification, "display"),
                               (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.unavailableReasons.insert(reason); self?.onUnavailable?() }
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "sleep"),
                               (NSWorkspace.screensDidWakeNotification, "display"),
                               (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.unavailableReasons.remove(reason); self?.onResume?() }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        lockObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.unavailableReasons.insert("lock"); self?.onUnavailable?() }
        })
        lockObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.unavailableReasons.remove("lock"); self?.onResume?() }
        })
    }
}
