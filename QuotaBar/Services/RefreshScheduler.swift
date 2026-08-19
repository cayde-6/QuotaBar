import AppKit
import Foundation

/// Drives QuotaStore's two "nobody asked for this" refresh triggers: the recurring
/// auto-refresh timer, and a refresh after the system wakes from sleep. Neither trigger
/// is ever allowed to prompt for Keychain access — see the comments below.
@MainActor
final class RefreshScheduler {
    /// Called on every trigger. `userInitiated` is always false — both triggers here are
    /// background refreshes, never one the user asked for.
    var onTick: ((Bool) -> Void)?

    /// Supplies the timestamp of the most recent fetch attempt across all providers, so
    /// `refreshAfterWakeIfNeeded` can skip a redundant refresh right after one just ran.
    var mostRecentAttempt: (() -> Date?)?

    private var autoRefreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    /// Cancels any existing loop and starts a fresh one — called at startup and again
    /// every time `refreshIntervalMinutes` changes, so a new interval takes effect on the
    /// very next tick instead of after whatever wait was already in progress.
    func startAutoRefreshLoop(intervalMinutes: Int) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(intervalMinutes) * 60))
                guard !Task.isCancelled else { return }
                self?.onTick?(false) // never allowed to prompt for Keychain access
            }
        }
    }

    func observeSystemWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAfterWakeIfNeeded()
            }
        }
    }

    private func refreshAfterWakeIfNeeded() {
        if let mostRecentAttempt = mostRecentAttempt?(), Date().timeIntervalSince(mostRecentAttempt) < 60 {
            return
        }
        onTick?(false) // never allowed to prompt for Keychain access
    }

    deinit {
        // deinit is nonisolated by default; RefreshScheduler only ever deallocates on
        // the main thread (it's held by QuotaStore for the app's lifetime), so this is safe.
        MainActor.assumeIsolated {
            autoRefreshTask?.cancel()
            if let wakeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            }
        }
    }
}
