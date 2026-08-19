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
}

/// Snapshot of quota data for one provider, as returned by a successful fetch.
struct ProviderQuota: Sendable, Equatable {
    let shortWindow: QuotaWindow?
    let weeklyWindow: QuotaWindow?
    let fetchedAt: Date
}

enum QuotaProvider: String, Sendable, CaseIterable {
    case codex, claude

    var displayName: String { self == .codex ? "CODEX" : "CLAUDE" }
}

enum QuotaError: Error, Sendable, Equatable {
    case cliNotFound          // CLI not installed / not found in PATH
    case notAuthenticated     // no credentials / not signed in
    case tokenExpired         // access token expired — waiting for the CLI to refresh it itself
    case unauthorized         // 401/403 from the backend
    case network(String)      // network error / timeout, short description
    case malformedResponse    // response shape changed / missing expected fields
    case keychainDenied       // user was prompted and explicitly declined Keychain access
    case keychainAccessNeeded // Keychain needs to prompt but interaction wasn't allowed (background refresh)
    case timedOut             // QuotaStore gave up waiting; the call may still be running

    var message: String {
        switch self {
        case .cliNotFound: return "Codex CLI not found"
        case .notAuthenticated: return "Not signed in"
        case .tokenExpired: return "Token expired — waiting for CLI refresh"
        case .unauthorized: return "Access denied"
        case .network(let reason): return "Network: \(reason)"
        case .malformedResponse: return "Unexpected response format"
        case .keychainDenied: return "Keychain access denied"
        case .keychainAccessNeeded: return "Keychain access needed — click Refresh"
        case .timedOut: return "Timed out — still waiting"
        }
    }
}

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

extension QuotaWindow {
    /// Converts a 0...100 utilization percentage into a remaining percentage, clamped to 0...100.
    init(utilization: Double, resetsAt: Date?) {
        self.remainingPercentage = max(0, min(100, 100 - utilization))
        self.resetsAt = resetsAt
    }
}
