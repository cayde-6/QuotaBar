import AppKit
import Foundation
import Observation

/// Central state holder: owns both providers, runs refreshes, and exposes the
/// latest known state for the status bar and popover to render.
@MainActor
@Observable
final class QuotaStore {
    var codex = ProviderState()
    var claude = ProviderState()
    var lastSuccessfulUpdate: Date?

    /// True while at least one provider has a fetch in flight. Derived from the two
    /// per-provider flags below rather than stored, so it's always consistent with them.
    var isRefreshing: Bool {
        codexInFlight || claudeInFlight
    }

    /// One of `validRefreshIntervalsMinutes`, persisted across launches. Changing this
    /// restarts the auto-refresh loop immediately at the new interval — it does not, by
    /// itself, trigger a refresh.
    var refreshIntervalMinutes: Int = QuotaStore.loadRefreshIntervalMinutes() {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.refreshIntervalDefaultsKey)
            startAutoRefreshLoop()
        }
    }

    static let validRefreshIntervalsMinutes = [1, 5, 15, 30, 60]
    private static let refreshIntervalDefaultsKey = "refreshIntervalMinutes"
    private static let defaultRefreshIntervalMinutes = 5

    /// Falls back to the default for a never-set key (`integer(forKey:)` reads 0, which
    /// isn't a valid option) or any other value outside the fixed list — e.g. leftover
    /// garbage from a future version with more choices.
    private static func loadRefreshIntervalMinutes() -> Int {
        let stored = UserDefaults.standard.integer(forKey: refreshIntervalDefaultsKey)
        return validRefreshIntervalsMinutes.contains(stored) ? stored : defaultRefreshIntervalMinutes
    }

    /// Called on the main actor whenever state changes, so the status bar image can be redrawn.
    /// A plain closure is simpler here than observation-tracking machinery for a single observer.
    var onUpdate: (() -> Void)?

    private let codexProvider = CodexQuotaProvider()
    private let claudeProvider = ClaudeQuotaProvider()

    // Two flags per provider, tracked separately (not jointly) so a provider stuck on a
    // call the store has no way to cancel (e.g. a Keychain read blocked on a system
    // prompt) can neither hide the other provider's data nor pile up repeat requests
    // against itself:
    // - inFlight: the store is currently waiting on this provider.
    // - abandoned: the store gave up waiting (timeout fired), but the call is still
    //   running in the background and hasn't reported in yet.
    // A new request only starts once BOTH are clear (see refreshProvider), which is
    // what stops timed-out calls from queuing up against a still-blocked provider.
    private var codexInFlight = false
    private var codexAbandoned = false
    private var claudeInFlight = false
    private var claudeAbandoned = false

    /// How long the STORE waits for a provider before giving up — not a timeout on the
    /// operation itself. Codex's own 25s timeout and Claude's 20s network timeout are
    /// both comfortably inside this, so in practice this only ever fires while a
    /// provider is stuck somewhere neither of them bounds — namely
    /// ClaudeQuotaProvider's synchronous Keychain read blocked on a system dialog,
    /// which can stay open indefinitely. The call itself is not cancelled by this and
    /// keeps running after it fires; refreshProvider still applies its result once it
    /// eventually arrives, it just isn't waited for.
    private let providerTimeout: TimeInterval = 30

    private var autoRefreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        refresh(userInitiated: true) // the one automatic refresh allowed to prompt for Keychain access
        startAutoRefreshLoop()
        observeSystemWake()
    }

    /// Refreshes both providers independently: each publishes its own result to state as
    /// soon as it's ready, rather than waiting for both, so one stuck provider can never
    /// hide the other's already-available data. Idempotent — safe to call repeatedly
    /// (e.g. from a manual Refresh click) since refreshProvider skips a provider that
    /// already has a request in flight or abandoned.
    ///
    /// `userInitiated` is passed straight through to ClaudeQuotaProvider as
    /// `allowInteraction`: pass `true` only for a refresh the user actually asked for
    /// (app launch, the Refresh button) — never for the auto-refresh timer or a
    /// post-wake refresh, or a rewritten Keychain item could pop up a system dialog
    /// completely unprompted.
    func refresh(userInitiated: Bool) {
        let codexProvider = self.codexProvider
        refreshProvider(
            fetch: { try await codexProvider.fetch() },
            state: \.codex,
            inFlight: \.codexInFlight,
            abandoned: \.codexAbandoned
        )

        let claudeProvider = self.claudeProvider
        refreshProvider(
            fetch: { try await claudeProvider.fetch(allowInteraction: userInitiated) },
            state: \.claude,
            inFlight: \.claudeInFlight,
            abandoned: \.claudeAbandoned
        )
    }

    /// One provider's refresh cycle, parameterized over which stored properties it reads
    /// and writes. (refreshCodex/refreshClaude used to be ~20 duplicated lines each.)
    private func refreshProvider(
        fetch: @escaping @Sendable () async throws -> ProviderQuota,
        state: ReferenceWritableKeyPath<QuotaStore, ProviderState>,
        inFlight: ReferenceWritableKeyPath<QuotaStore, Bool>,
        abandoned: ReferenceWritableKeyPath<QuotaStore, Bool>
    ) {
        guard !self[keyPath: inFlight], !self[keyPath: abandoned] else { return }
        self[keyPath: inFlight] = true
        self[keyPath: state].lastAttempt = Date()

        let timeout = providerTimeout
        let gate = FetchGate()

        // The real call. However long it actually takes, its result is always applied
        // once it arrives — even if the timeout below already gave up waiting on it.
        Task { [weak self] in
            let outcome: Result<ProviderQuota, QuotaError>
            do {
                outcome = .success(try await fetch())
            } catch let error as QuotaError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.network("request failed"))
            }

            guard let self else { return }
            if await gate.markOperationFinished() {
                // The timeout already fired for this call — this is a late result;
                // `inFlight` was already cleared when the timeout fired.
                self[keyPath: abandoned] = false
            } else {
                self[keyPath: inFlight] = false
            }
            self.apply(outcome, to: state)
            self.onUpdate?()
        }

        // The store-side timeout. It stops the STORE from waiting — it cannot cancel
        // the Task above (a blocked synchronous Keychain call inside an actor can't be
        // preempted), so the two Tasks race independently rather than one owning the
        // other's lifetime; FetchGate arbitrates which of them acts first.
        Task { [weak self] in
            // This Task is unstructured, so it isn't cancelled when anything else is —
            // `try?` here can only ever swallow a genuine timeout firing. If this is
            // ever restructured to run as a child of a cancellable parent, `try?`
            // would start swallowing that cancellation too and fire an instant false
            // timeout, so that change would need to handle CancellationError explicitly.
            try? await Task.sleep(for: .seconds(timeout))
            guard let self else { return }
            guard await gate.markTimedOut() else { return } // operation already finished
            self[keyPath: inFlight] = false
            self[keyPath: abandoned] = true
            self[keyPath: state].lastError = .timedOut
            self.onUpdate?()
        }
    }

    private func apply(_ outcome: Result<ProviderQuota, QuotaError>, to state: ReferenceWritableKeyPath<QuotaStore, ProviderState>) {
        switch outcome {
        case .success(let quota):
            self[keyPath: state].quota = quota
            self[keyPath: state].lastError = nil
            lastSuccessfulUpdate = Date()
        case .failure(let error):
            self[keyPath: state].lastError = error
        }
    }

    /// Cancels any existing loop and starts a fresh one — called at startup and again
    /// every time `refreshIntervalMinutes` changes, so a new interval takes effect on the
    /// very next tick instead of after whatever wait was already in progress.
    private func startAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let minutes = self?.refreshIntervalMinutes ?? 5
                try? await Task.sleep(for: .seconds(Double(minutes) * 60))
                guard !Task.isCancelled else { return }
                self?.refresh(userInitiated: false) // never allowed to prompt for Keychain access
            }
        }
    }

    private func observeSystemWake() {
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
        if let mostRecentAttempt, Date().timeIntervalSince(mostRecentAttempt) < 60 {
            return
        }
        refresh(userInitiated: false) // never allowed to prompt for Keychain access
    }

    private var mostRecentAttempt: Date? {
        switch (codex.lastAttempt, claude.lastAttempt) {
        case let (a?, b?): return max(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    deinit {
        // deinit is nonisolated by default; QuotaStore only ever deallocates on the main
        // thread (it's held by AppDelegate for the app's lifetime), so this is safe.
        MainActor.assumeIsolated {
            autoRefreshTask?.cancel()
            if let wakeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            }
        }
    }
}

/// Coordinates the two Tasks in refreshProvider (the real call, and the store's
/// timeout) so exactly one of them is treated as "first" — the operation finishing
/// before the timeout, or the timeout firing before the operation finishes — and the
/// other reacts to that instead of double-applying or contradicting it.
private actor FetchGate {
    private var operationFinished = false
    private var timedOut = false

    /// Called when the real operation finishes. Returns whether the timeout had
    /// already fired for this call (i.e. this is a late, previously-abandoned result).
    func markOperationFinished() -> Bool {
        operationFinished = true
        return timedOut
    }

    /// Called when the timeout fires. Returns whether the store should still act on
    /// it — false if the operation already finished first.
    func markTimedOut() -> Bool {
        guard !operationFinished else { return false }
        timedOut = true
        return true
    }
}
