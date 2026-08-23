import Foundation
import Observation

/// Polls GitHub Releases for a newer QuotaBar version than the one currently running.
/// Purely informational — never auto-updates, never surfaces errors, since this is a
/// background check nobody asked for and a flaky network shouldn't nag about it.
@MainActor
@Observable
final class UpdateChecker {
    private(set) var availableUpdate: (version: String, releaseURL: URL)?

    private var pollTask: Task<Void, Never>?

    private struct LatestRelease: Decodable {
        let tag_name: String
        let html_url: String
    }

    func checkForUpdate() async {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/cayde-6/QuotaBar/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let release = try? JSONDecoder().decode(LatestRelease.self, from: data),
              let releaseURL = URL(string: release.html_url) else {
            return
        }

        let remoteVersion = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        if Self.isVersion(remoteVersion, newerThan: currentVersion) {
            availableUpdate = (version: release.tag_name, releaseURL: releaseURL)
        } else {
            availableUpdate = nil
        }
    }

    /// Compares versions component-by-component as [Int] (major.minor.patch), not as
    /// strings — string comparison would rank "1.10.0" below "1.9.0".
    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsParts.count, rhsParts.count)
        for i in 0..<count {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Checks immediately, then every 12 hours. Cancels any existing loop first, matching
    /// RefreshScheduler's pattern, though this is only ever called once at startup.
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdate()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(12 * 3600))
            }
        }
    }

    deinit {
        // deinit is nonisolated by default; UpdateChecker only ever deallocates on the
        // main thread (it's held by QuotaStore for the app's lifetime), so this is safe.
        MainActor.assumeIsolated {
            pollTask?.cancel()
        }
    }
}
