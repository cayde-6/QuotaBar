import Foundation

/// A single rate-limit window (e.g. "5 hour" or "weekly") for a provider.
struct QuotaWindow: Sendable, Equatable {
    /// 0...100
    let remainingPercentage: Double
    let resetsAt: Date?
}

/// Coarse severity bucket for a window's remaining percentage. Kept in one place so the
/// menu bar readout and the popover always agree on where the thresholds fall.
enum QuotaLevel: Sendable {
    case healthy, warning, critical
}

extension QuotaWindow {
    /// The integer percentage actually shown to the user. Both `level` and every UI
    /// label are derived from this rounded value, not from the raw `remainingPercentage`
    /// — otherwise the digits on screen and the color on screen can disagree (e.g. a
    /// true 49.6% displays as "50%" but would classify as `.warning` off the raw value).
    var displayedPercent: Int {
        Int(remainingPercentage.rounded())
    }

    /// `>= 50%` remaining is healthy, `>= 20%` is a warning, anything less is critical.
    var level: QuotaLevel {
        let percent = displayedPercent
        if percent >= 50 { return .healthy }
        if percent >= 20 { return .warning }
        return .critical
    }

    /// Converts a 0...100 utilization percentage into a remaining percentage, clamped to 0...100.
    init(utilization: Double, resetsAt: Date?) {
        self.remainingPercentage = max(0, min(100, 100 - utilization))
        self.resetsAt = resetsAt
    }
}
