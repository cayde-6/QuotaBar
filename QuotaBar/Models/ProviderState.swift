import Foundation

/// Latest known state for one provider. Failures never discard the last valid quota.
struct ProviderState: Sendable {
    var quota: ProviderQuota?        // last VALID data, retained across errors
    var lastError: QuotaError?       // error from the most recent attempt, nil on success
    var lastAttempt: Date?

    /// True when there is no data yet, or the data is older than 20 minutes.
    var isStale: Bool {
        guard let fetchedAt = quota?.fetchedAt else { return true }
        return Date().timeIntervalSince(fetchedAt) > 20 * 60
    }

    /// True when this provider has never produced valid data and the last error
    /// means it isn't set up on this machine at all (see `QuotaProvider.indicatesMissingSetup`).
    /// Once any valid quota has been seen, the provider is never considered missing again —
    /// stale data is better shown than hidden.
    func isMissing(for provider: QuotaProvider) -> Bool {
        guard quota == nil, let lastError else { return false }
        return provider.indicatesMissingSetup(lastError)
    }
}
