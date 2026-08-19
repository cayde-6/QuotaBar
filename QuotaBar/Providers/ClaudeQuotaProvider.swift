import Foundation
import Security

/// Read-only reader of Claude Code's own OAuth credentials, used to query the
/// account's usage/rate-limit endpoint. Never refreshes or stores tokens itself.
actor ClaudeQuotaProvider {
    private let timeout: TimeInterval = 20

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

        let credentials = try loadCredentials(allowInteraction: allowInteraction)

        let expiresAt = Date(timeIntervalSince1970: TimeInterval(credentials.expiresAtMillis) / 1000)
        guard expiresAt > Date() else {
            // Never attempt to refresh — Claude Code owns that lifecycle.
            throw QuotaError.tokenExpired
        }

        return try await fetchUsage(accessToken: credentials.accessToken)
    }

    // MARK: - Credentials lookup

    private struct Credentials {
        let accessToken: String
        let expiresAtMillis: Int64
    }

    /// Thrown internally by `readFromKeychain` so `loadCredentials` can see the raw
    /// `OSStatus` and decide between "not signed in" and "a file elsewhere was malformed".
    private struct KeychainLookupFailure: Error {
        let status: OSStatus
    }

    private func loadCredentials(allowInteraction: Bool) throws -> Credentials {
        // A source that exists but fails to parse must not block the fallback chain —
        // e.g. a leftover ~/.claude/.credentials.json in an old format should not hide
        // working credentials that are actually sitting in the Keychain.
        var sawMalformedFile = false

        if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !configDir.isEmpty {
            let url = URL(fileURLWithPath: configDir).appendingPathComponent(".credentials.json")
            if let data = try? Data(contentsOf: url) {
                if let credentials = try? parseCredentials(data) {
                    return credentials
                }
                sawMalformedFile = true
            }
        }

        let homeCredentials = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: homeCredentials) {
            if let credentials = try? parseCredentials(data) {
                return credentials
            }
            sawMalformedFile = true
        }

        do {
            let keychainData = try readFromKeychain()
            return try parseCredentials(keychainData)
        } catch let failure as KeychainLookupFailure {
            if failure.status == errSecItemNotFound, sawMalformedFile {
                // No item in the Keychain, but a file elsewhere existed and was broken —
                // that's a more useful diagnosis than "not signed in".
                throw QuotaError.malformedResponse
            }
            throw classifyKeychainError(failure.status, allowInteraction: allowInteraction)
        }
    }

    private func readFromKeychain() throws -> Data {
        let service = "Claude Code-credentials"

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            query.removeValue(forKey: kSecAttrAccount as String)
            item = nil
            status = SecItemCopyMatching(query as CFDictionary, &item)
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainLookupFailure(status: status)
        }
        return data
    }

    /// `errSecAuthFailed`/`errSecInteractionNotAllowed` mean two different things depending
    /// on whether a prompt was even allowed to appear: with interaction allowed, they mean
    /// the user actually declined it (`.keychainDenied`); with interaction disabled up
    /// front, they mean the Keychain has something to ask but wasn't allowed to ask it
    /// (`.keychainAccessNeeded`) — a background refresh hitting this isn't a denial, it's
    /// just not the moment to prompt.
    private func classifyKeychainError(_ status: OSStatus, allowInteraction: Bool) -> QuotaError {
        switch status {
        case errSecItemNotFound:
            return .notAuthenticated
        case errSecAuthFailed, errSecInteractionNotAllowed:
            return allowInteraction ? .keychainDenied : .keychainAccessNeeded
        case errSecUserCanceled:
            return .keychainDenied
        default:
            return .notAuthenticated
        }
    }

    private func parseCredentials(_ data: Data) throws -> Credentials {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let expiresAt = (oauth["expiresAt"] as? NSNumber)?.int64Value else {
            throw QuotaError.malformedResponse
        }
        return Credentials(accessToken: accessToken, expiresAtMillis: expiresAt)
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

        return try parseUsage(data)
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

    // MARK: - Response parsing

    private func parseUsage(_ data: Data) throws -> ProviderQuota {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.malformedResponse
        }

        let shortWindow = parseWindow(object["five_hour"])
        let weeklyWindow = parseWindow(object["seven_day"])

        guard shortWindow != nil || weeklyWindow != nil else {
            throw QuotaError.malformedResponse
        }

        return ProviderQuota(shortWindow: shortWindow, weeklyWindow: weeklyWindow, fetchedAt: Date())
    }

    private func parseWindow(_ raw: Any?) -> QuotaWindow? {
        guard let dict = raw as? [String: Any],
              let utilization = (dict["utilization"] as? NSNumber)?.doubleValue else {
            return nil
        }
        let resetsAt = (dict["resets_at"] as? String).flatMap(parseDate)
        return QuotaWindow(utilization: utilization, resetsAt: resetsAt)
    }

    /// Tries progressively looser ISO-8601 parsers, since the API's fractional-seconds
    /// format isn't accepted by every formatter. Falls back to a nil reset date rather
    /// than dropping the whole window — the percentage matters more than the date.
    private func parseDate(_ string: String) -> Date? {
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFraction.date(from: string) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }

        let formatterWithFraction = DateFormatter()
        formatterWithFraction.locale = Locale(identifier: "en_US_POSIX")
        formatterWithFraction.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        if let date = formatterWithFraction.date(from: string) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.date(from: string)
    }
}

/// Globally enables or disables whether ANY Keychain access in this process may show a
/// system authentication prompt. QuotaBar defaults this to `false` at launch (see
/// `QuotaBarMain.main()`) and `ClaudeQuotaProvider.fetch(allowInteraction:)` is the only
/// place that ever flips it on, and only for as long as one specific call needs it.
///
/// `SecKeychainSetUserInteractionAllowed` is deprecated because it's part of the legacy
/// file-based Keychain API — but Claude Code's own credential item lives in exactly that
/// legacy file-based keychain (not the modern data-protection keychain), so there is no
/// non-deprecated replacement that reaches it. The resulting deprecation warning is left
/// in place, deliberately, on the one line below that calls it: Swift has no way to
/// suppress a diagnostic line-by-line, and marking this wrapper itself `@available(...,
/// deprecated)` doesn't remove the warning, it just relocates it to every one of this
/// function's own callers instead (verified — that turned one warning into three).
/// A single warning at its one true source is the best available outcome.
func setKeychainInteractionAllowed(_ allowed: Bool) {
    SecKeychainSetUserInteractionAllowed(allowed)
}
