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
}
