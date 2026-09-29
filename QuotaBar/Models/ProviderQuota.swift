import Foundation

/// Snapshot of quota data for one provider, as returned by a successful fetch.
struct ProviderQuota: Sendable, Equatable {
    let shortWindow: QuotaWindow?
    let weeklyWindow: QuotaWindow?
    /// Plans that meter spend rather than time (Codex `business`) report no rolling
    /// windows at all — `shortWindow` and `weeklyWindow` are both nil — and this instead.
    let planWindow: QuotaWindow?
    let fetchedAt: Date

    /// Lead with the shortest available limit. Codex can report only its weekly window
    /// while the five-hour limit is unavailable.
    var headlineWindow: QuotaWindow? { shortWindow ?? weeklyWindow ?? planWindow }

    /// A second number is useful only when both rolling windows are present. In
    /// particular, a weekly-only limit must not appear twice in the menu bar.
    var secondaryWindow: QuotaWindow? { shortWindow == nil ? nil : weeklyWindow }
}
