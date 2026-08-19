import Foundation

/// Snapshot of quota data for one provider, as returned by a successful fetch.
struct ProviderQuota: Sendable, Equatable {
    let shortWindow: QuotaWindow?
    let weeklyWindow: QuotaWindow?
    let fetchedAt: Date
}
