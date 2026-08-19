import Foundation

/// Read-only reader of Claude Code's own OAuth credentials, used to query the
/// account's usage/rate-limit endpoint. Never refreshes or stores tokens itself.
actor ClaudeQuotaProvider: QuotaProviding {
    private let timeout: TimeInterval = 20
    private let credentialsStore = ClaudeCredentialsStore()

    /// `allowInteraction` controls whether the Keychain read below is allowed to show a
    /// system authentication prompt. Keychain interaction is disabled process-wide by
    /// default (see QuotaBarMain.main()); this temporarily lifts that only for the
    /// duration of this call, and only when the caller says this is one of the two
    /// refreshes a user actually asked for (first launch, manual Refresh) — see
    /// QuotaStore.refresh(userInitiated:). Every other refresh path (timer, wake) passes
    /// false, so a stale/rewritten Keychain item can never pop up a system dialog on its own.
    func fetch(allowInteraction: Bool) async throws -> ProviderQuota {
        if allowInteraction {
            setKeychainInteractionAllowed(true)
        }
        defer {
            // Unconditional and unconditionally restores the default-off state, on every
            // exit path (success, thrown error) — never leave interaction enabled.
            if allowInteraction {
                setKeychainInteractionAllowed(false)
            }
        }

        let credentials = try credentialsStore.load(allowInteraction: allowInteraction)

        let expiresAt = Date(timeIntervalSince1970: TimeInterval(credentials.expiresAtMillis) / 1000)
        guard expiresAt > Date() else {
            // Never attempt to refresh — Claude Code owns that lifecycle.
            throw QuotaError.tokenExpired
        }

        return try await fetchUsage(accessToken: credentials.accessToken)
    }

    // MARK: - Usage request

    private func fetchUsage(accessToken: String) async throws -> ProviderQuota {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("QuotaBar/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        // Ephemeral session: nothing is cached or persisted to disk.
        let session = URLSession(configuration: .ephemeral)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw QuotaError.network(shortNetworkDescription(error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw QuotaError.network("no response")
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw QuotaError.unauthorized
            }
            throw QuotaError.network("HTTP \(http.statusCode)")
        }

        return try ClaudeUsageResponse.parseUsage(data)
    }

    private func shortNetworkDescription(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorTimedOut: return "timeout"
        case NSURLErrorNotConnectedToInternet: return "offline"
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorNetworkConnectionLost:
            return "unreachable"
        default: return "request failed"
        }
    }
}
