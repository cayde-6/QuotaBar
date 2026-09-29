import Foundation

/// A single rate-limit window as returned by codex app-server's `account/rateLimits/read`,
/// before it's been classified into "short" (5h) vs "weekly".
struct RawWindow {
    let usedPercent: Double
    let windowDurationMins: Int64?
    let resetsAt: Int64?
}

/// Pure parsing/classification of codex app-server's rate-limit JSON-RPC result — a
/// function of JSON in, `ProviderQuota` out, with no actor affinity, so it can be
/// called directly from a test.
enum CodexRateLimitParser {
    static func parseWindow(_ dict: [String: Any]) throws -> RawWindow {
        guard let usedPercent = (dict["usedPercent"] as? NSNumber)?.doubleValue else {
            throw QuotaError.malformedResponse
        }
        let windowDurationMins = (dict["windowDurationMins"] as? NSNumber)?.int64Value
        let resetsAt = (dict["resetsAt"] as? NSNumber)?.int64Value
        return RawWindow(usedPercent: usedPercent, windowDurationMins: windowDurationMins, resetsAt: resetsAt)
    }

    /// Classifies the primary/secondary windows into short (5h) and weekly buckets by duration,
    /// not by position — on this CLI version `primary` can hold the weekly window. When both
    /// windows are present, the longest always wins `weekly`, but the short slot never accepts
    /// a window longer than a day (`windowDurationMins > 1440`): if even the shorter of the two
    /// windows is week/month-scale, there is no real "5 hour" window to show, and a mislabeled
    /// weekly or monthly number under that heading is misleading — so `short` comes
    /// back nil and the UI shows only the weekly limit.
    static func classify(primary: RawWindow?, secondary: RawWindow?) -> (short: RawWindow?, weekly: RawWindow?) {
        let windows = [primary, secondary].compactMap { $0 }

        switch windows.count {
        case 0:
            return (nil, nil)
        case 1:
            let window = windows[0]
            if let mins = window.windowDurationMins {
                return mins <= 1440 ? (window, nil) : (nil, window)
            }
            // Legacy fallback when duration is missing: primary is short, secondary is weekly.
            return primary != nil ? (window, nil) : (nil, window)
        default:
            // Two windows — `a` is primary, `b` is secondary (the only way to reach this
            // branch with exactly two RawWindows). Handled as three explicit cases rather
            // than "sort with missing durations pushed last": that scheme misclassified a
            // pair where only one window has a duration, since the nil-duration window
            // (which can easily be the real 5-hour window) always lost the sort and got
            // discarded instead of falling into the other slot.
            let a = windows[0]
            let b = windows[1]

            switch (a.windowDurationMins, b.windowDurationMins) {
            case let (aMins?, bMins?):
                // Both known: shorter wins `short` (but only if it's actually <=1440),
                // longer wins `weekly`. Equal durations tie toward position (a, i.e.
                // primary, is treated as the "shorter" one) so the result is deterministic.
                let (shorter, longer) = aMins <= bMins ? (a, b) : (b, a)
                let short = (shorter.windowDurationMins ?? 0) <= 1440 ? shorter : nil
                return (short, longer)
            case let (aMins?, nil):
                // Only `a` has a duration: classify it by threshold, `b` takes the other slot.
                return aMins <= 1440 ? (a, b) : (b, a)
            case let (nil, bMins?):
                return bMins <= 1440 ? (b, a) : (a, b)
            case (nil, nil):
                // Legacy fallback when neither has a duration: primary short, secondary weekly.
                return (a, b)
            }
        }
    }

    /// Parses the `individualLimit` block a `business`-plan account reports instead of
    /// rolling windows: a flat spend cap with no 5-hour/weekly split. Returns nil rather
    /// than throwing when the block is absent or unusable — plans with normal windows
    /// simply don't have this key, and that's not an error.
    static func parsePlanWindow(_ dict: [String: Any]) -> QuotaWindow? {
        let resetsAt = (dict["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: TimeInterval($0.int64Value)) }

        // `remainingPercent` is already a remaining percentage, unlike the `usedPercent`
        // on primary/secondary windows — build the window directly from it, with no
        // 100-minus flip, or a low remaining balance would display as nearly full.
        if let remainingPercent = (dict["remainingPercent"] as? NSNumber)?.doubleValue {
            return QuotaWindow(remainingPercentage: max(0, min(100, remainingPercent)), resetsAt: resetsAt)
        }

        // Fallback: `limit` and `used` arrive as strings (e.g. "50000", "47.57...").
        // Compute the remaining percentage ourselves, guarding against a zero or
        // non-numeric limit rather than dividing by zero.
        guard let limitString = dict["limit"] as? String, let limit = Double(limitString), limit > 0,
              let usedString = dict["used"] as? String, let used = Double(usedString) else {
            return nil
        }
        let remaining = max(0, min(100, 100 - used / limit * 100))
        return QuotaWindow(remainingPercentage: remaining, resetsAt: resetsAt)
    }

    static func extractRateLimits(_ result: [String: Any]) -> [String: Any]? {
        if let rateLimits = result["rateLimits"] as? [String: Any] {
            return rateLimits
        }
        if let byLimitId = result["rateLimitsByLimitId"] as? [String: Any] {
            if let codex = byLimitId["codex"] as? [String: Any] {
                return codex
            }
            // Dictionary iteration order is unspecified — pick the lexicographically
            // smallest key so repeated calls with the same data agree with each other.
            if let smallestKey = byLimitId.keys.sorted().first, let value = byLimitId[smallestKey] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    static func parseRateLimits(_ result: [String: Any]) throws -> ProviderQuota {
        guard let rateLimits = extractRateLimits(result) else {
            throw QuotaError.malformedResponse
        }

        let primaryDict = rateLimits["primary"] as? [String: Any]
        let secondaryDict = rateLimits["secondary"] as? [String: Any]

        // Both windows being absent is a normal state for a fresh account with zero
        // consumption, not an auth failure — real auth errors are caught in
        // classifyRPCError before we ever get here. Report that no limit data exists.
        let primary = try primaryDict.map(parseWindow)
        let secondary = try secondaryDict.map(parseWindow)
        let (shortRaw, weeklyRaw) = classify(primary: primary, secondary: secondary)

        func makeWindow(_ raw: RawWindow?) -> QuotaWindow? {
            guard let raw else { return nil }
            let resetsAt = raw.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            return QuotaWindow(utilization: raw.usedPercent, resetsAt: resetsAt)
        }

        let shortWindow = makeWindow(shortRaw)
        let weeklyWindow = makeWindow(weeklyRaw)

        // The plan window is only meaningful when there are no rolling windows to show
        // instead — a business account with primary/secondary present shouldn't also
        // show a plan limit, since that would put two different meanings of "remaining"
        // on screen at once.
        let planWindow: QuotaWindow?
        if shortWindow == nil, weeklyWindow == nil, let individualLimit = rateLimits["individualLimit"] as? [String: Any] {
            planWindow = parsePlanWindow(individualLimit)
        } else {
            planWindow = nil
        }

        return ProviderQuota(shortWindow: shortWindow, weeklyWindow: weeklyWindow, planWindow: planWindow, fetchedAt: Date())
    }
}
