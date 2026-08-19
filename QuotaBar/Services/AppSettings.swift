import Foundation

/// Persists user-facing app settings across launches.
enum AppSettings {
    static let validRefreshIntervalsMinutes = [1, 5, 15, 30, 60]
    private static let refreshIntervalDefaultsKey = "refreshIntervalMinutes"
    private static let defaultRefreshIntervalMinutes = 5

    /// One of `validRefreshIntervalsMinutes`. Falls back to the default for a never-set
    /// key (`integer(forKey:)` reads 0, which isn't a valid option) or any other value
    /// outside the fixed list — e.g. leftover garbage from a future version with more
    /// choices.
    static var refreshIntervalMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: refreshIntervalDefaultsKey)
            return validRefreshIntervalsMinutes.contains(stored) ? stored : defaultRefreshIntervalMinutes
        }
        set {
            UserDefaults.standard.set(newValue, forKey: refreshIntervalDefaultsKey)
        }
    }
}
