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

    /// True while at least one provider has a fetch in flight. A stored flag, updated
    /// from ProviderRefresher's onEvent callbacks, rather than computed on read — plain
    /// computed access into the two ProviderRefresher instances wouldn't be tracked by
    /// @Observable, so SwiftUI would never see it change.
    private(set) var isRefreshing = false

    /// One of `validRefreshIntervalsMinutes`, persisted across launches. Changing this
    /// restarts the auto-refresh loop immediately at the new interval — it does not, by
    /// itself, trigger a refresh.
    var refreshIntervalMinutes: Int = AppSettings.refreshIntervalMinutes {
        didSet {
            AppSettings.refreshIntervalMinutes = refreshIntervalMinutes
            refreshScheduler.startAutoRefreshLoop(intervalMinutes: refreshIntervalMinutes)
        }
    }

    static var validRefreshIntervalsMinutes: [Int] { AppSettings.validRefreshIntervalsMinutes }

    /// Called on the main actor whenever state changes, so the status bar image can be redrawn.
    /// A plain closure is simpler here than observation-tracking machinery for a single observer.
    var onUpdate: (() -> Void)?

    /// A newer release than the one running, if the periodic GitHub check found one.
    var availableUpdate: (version: String, releaseURL: URL)? { updateChecker.availableUpdate }

    private let codexRefresher = ProviderRefresher(provider: CodexQuotaProvider())
    private let claudeRefresher = ProviderRefresher(provider: ClaudeQuotaProvider())
    private let refreshScheduler = RefreshScheduler()
    private let updateChecker = UpdateChecker()

    init() {
        codexRefresher.onEvent = { [weak self] event in self?.apply(event, to: \.codex) }
        claudeRefresher.onEvent = { [weak self] event in self?.apply(event, to: \.claude) }
        refreshScheduler.onTick = { [weak self] userInitiated in self?.refresh(userInitiated: userInitiated) }
        refreshScheduler.mostRecentAttempt = { [weak self] in self?.mostRecentAttempt }
        updateChecker.startPolling()
    }

    func start() {
        refresh(userInitiated: true) // the one automatic refresh allowed to prompt for Keychain access
        refreshScheduler.startAutoRefreshLoop(intervalMinutes: refreshIntervalMinutes)
        refreshScheduler.observeSystemWake()
    }

    /// Refreshes both providers independently: each publishes its own result to state as
    /// soon as it's ready, rather than waiting for both, so one stuck provider can never
    /// hide the other's already-available data. Idempotent — safe to call repeatedly
    /// (e.g. from a manual Refresh click) since ProviderRefresher skips a provider that
    /// already has a request in flight or abandoned.
    ///
    /// `userInitiated` is passed straight through to ClaudeQuotaProvider as
    /// `allowInteraction`: pass `true` only for a refresh the user actually asked for
    /// (app launch, the Refresh button) — never for the auto-refresh timer or a
    /// post-wake refresh, or a rewritten Keychain item could pop up a system dialog
    /// completely unprompted.
    func refresh(userInitiated: Bool) {
        codexRefresher.refresh(userInitiated: userInitiated)
        claudeRefresher.refresh(userInitiated: userInitiated)
    }

    private func apply(_ event: ProviderRefreshEvent, to state: ReferenceWritableKeyPath<QuotaStore, ProviderState>) {
        switch event {
        case .started:
            self[keyPath: state].lastAttempt = Date()
        case .finished(.success(let quota)):
            self[keyPath: state].quota = quota
            self[keyPath: state].lastError = nil
            lastSuccessfulUpdate = Date()
        case .finished(.failure(let error)):
            self[keyPath: state].lastError = error
        case .timedOut:
            self[keyPath: state].lastError = .timedOut
        }
        isRefreshing = codexRefresher.isRefreshing || claudeRefresher.isRefreshing
        onUpdate?()
    }

    private var mostRecentAttempt: Date? {
        switch (codex.lastAttempt, claude.lastAttempt) {
        case let (a?, b?): return max(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }
}
