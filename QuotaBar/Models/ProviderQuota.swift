import Foundation

/// Snapshot of quota data for one provider, as returned by a successful fetch.
struct ProviderQuota: Sendable, Equatable {
    let shortWindow: QuotaWindow?
    let weeklyWindow: QuotaWindow?
    /// Plans that meter spend rather than time (Codex `business`) report no rolling
    /// windows at all — `shortWindow` and `weeklyWindow` are both nil — and this instead.
    let planWindow: QuotaWindow?
    let fetchedAt: Date

    /// The window to lead with: the short window normally, the plan's own limit on plans
    /// that have no windows.
    var headlineWindow: QuotaWindow? { shortWindow ?? planWindow }
}
