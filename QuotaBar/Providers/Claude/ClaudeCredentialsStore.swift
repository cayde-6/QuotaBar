import Foundation
import Security

/// Claude Code's own OAuth credentials, as read from disk or the Keychain.
struct ClaudeCredentials {
    let accessToken: String
    let expiresAtMillis: Int64
}

/// Read-only reader of Claude Code's own OAuth credentials. Never refreshes or stores
/// tokens itself.
struct ClaudeCredentialsStore {
    /// Thrown internally by `readFromKeychain` so `loadCredentials` can see the raw
    /// `OSStatus` and decide between "not signed in" and "a file elsewhere was malformed".
    private struct KeychainLookupFailure: Error {
        let status: OSStatus
    }

    func load(allowInteraction: Bool) throws -> ClaudeCredentials {
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

    private func parseCredentials(_ data: Data) throws -> ClaudeCredentials {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let expiresAt = (oauth["expiresAt"] as? NSNumber)?.int64Value else {
            throw QuotaError.malformedResponse
        }
        return ClaudeCredentials(accessToken: accessToken, expiresAtMillis: expiresAt)
    }
}
