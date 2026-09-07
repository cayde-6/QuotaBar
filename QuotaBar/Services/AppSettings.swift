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

    private static let surfaceModeDefaultsKey = "surfaceMode"

    /// Falls back to `.menuBar` for a never-set key or any raw value that isn't a known
    /// case (e.g. leftover garbage from a future version with more modes).
    static var surfaceMode: SurfaceMode {
        get {
            guard let stored = UserDefaults.standard.string(forKey: surfaceModeDefaultsKey) else { return .menuBar }
            return SurfaceMode(rawValue: stored) ?? .menuBar
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: surfaceModeDefaultsKey)
        }
    }

    private static let railEdgeDefaultsKey = "railEdge"
    private static let railFractionDefaultsKey = "railFraction"
    private static let railDisplayIDDefaultsKey = "railDisplayID"

    /// Falls back to `RailPlacement.default` as a whole on any invalid stored value
    /// (unrecognized edge, or a fraction outside 0...1) — a partially-garbled placement
    /// is more confusing than one reset entirely. `0` for the display ID means "no
    /// specific display" (`nil`), since `UserDefaults.integer(forKey:)` also reads `0`
    /// for a never-set key, which conveniently doubles as that same default.
    static var railPlacement: RailPlacement {
        get {
            let defaults = UserDefaults.standard
            guard
                let edgeRaw = defaults.string(forKey: railEdgeDefaultsKey),
                let edge = RailEdge(rawValue: edgeRaw),
                defaults.object(forKey: railFractionDefaultsKey) != nil
            else {
                return .default
            }
            let fraction = defaults.double(forKey: railFractionDefaultsKey)
            guard (0...1).contains(fraction) else { return .default }
            let storedDisplayID = defaults.integer(forKey: railDisplayIDDefaultsKey)
            if storedDisplayID == 0 {
                return RailPlacement(edge: edge, fraction: fraction, displayID: nil)
            }
            // `UInt32(storedDisplayID)` traps on a negative or out-of-range value instead
            // of failing gracefully — `UInt32(exactly:)` is the non-trapping form, and a
            // value it rejects is treated the same as any other garbled stored value.
            guard let displayID = UInt32(exactly: storedDisplayID) else { return .default }
            return RailPlacement(edge: edge, fraction: fraction, displayID: displayID)
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.edge.rawValue, forKey: railEdgeDefaultsKey)
            defaults.set(newValue.fraction, forKey: railFractionDefaultsKey)
            defaults.set(newValue.displayID.map(Int.init) ?? 0, forKey: railDisplayIDDefaultsKey)
        }
    }
}
