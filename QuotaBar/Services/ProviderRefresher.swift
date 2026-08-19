import Foundation

/// Runs one provider's fetch with a store-side timeout, and guarantees at most one
/// request in flight per provider.
@MainActor
final class ProviderRefresher {
    private let provider: any QuotaProviding

    /// How long the STORE waits for a provider before giving up — not a timeout on the
    /// operation itself. Codex's own 25s timeout and Claude's 20s network timeout are
    /// both comfortably inside this, so in practice this only ever fires while a
    /// provider is stuck somewhere neither of them bounds — namely
    /// ClaudeQuotaProvider's synchronous Keychain read blocked on a system dialog,
    /// which can stay open indefinitely. The call itself is not cancelled by this and
    /// keeps running after it fires; refreshProvider still applies its result once it
    /// eventually arrives, it just isn't waited for.
    private let timeout: TimeInterval

    // Two flags, tracked separately (not jointly) so a provider stuck on a call this
    // type has no way to cancel (e.g. a Keychain read blocked on a system prompt) can
    // neither hide the other provider's data nor pile up repeat requests against
    // itself:
    // - inFlight: the store is currently waiting on this provider.
    // - abandoned: the store gave up waiting (timeout fired), but the call is still
    //   running in the background and hasn't reported in yet.
    // A new request only starts once BOTH are clear (see refresh), which is
    // what stops timed-out calls from queuing up against a still-blocked provider.
    private var inFlight = false
    private var abandoned = false

    var onEvent: ((ProviderRefreshEvent) -> Void)?

    init(provider: any QuotaProviding, timeout: TimeInterval = 30) {
        self.provider = provider
        self.timeout = timeout
    }

    var isRefreshing: Bool { inFlight }

    func refresh(userInitiated: Bool) {
        guard !inFlight, !abandoned else { return }
        inFlight = true
        onEvent?(.started)

        let provider = self.provider
        let timeout = self.timeout
        let gate = FetchGate()

        // The real call. However long it actually takes, its result is always applied
        // once it arrives — even if the timeout below already gave up waiting on it.
        Task { [weak self] in
            let outcome: Result<ProviderQuota, QuotaError>
            do {
                outcome = .success(try await provider.fetch(allowInteraction: userInitiated))
            } catch let error as QuotaError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.network("request failed"))
            }

            guard let self else { return }
            if await gate.markOperationFinished() {
                // The timeout already fired for this call — this is a late result;
                // `inFlight` was already cleared when the timeout fired.
                self.abandoned = false
            } else {
                self.inFlight = false
            }
            self.onEvent?(.finished(outcome))
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
            self.inFlight = false
            self.abandoned = true
            self.onEvent?(.timedOut)
        }
    }
}

enum ProviderRefreshEvent {
    case started                                        // the attempt began
    case finished(Result<ProviderQuota, QuotaError>)    // the result arrived (possibly late)
    case timedOut                                       // the store gave up waiting
}

/// Coordinates the two Tasks in refresh() (the real call, and the store's timeout) so
/// exactly one of them is treated as "first" — the operation finishing before the
/// timeout, or the timeout firing before the operation finishes — and the other
/// reacts to that instead of double-applying or contradicting it.
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
