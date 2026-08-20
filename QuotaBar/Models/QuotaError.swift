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
    // A failure we couldn't attribute to any of the categories above. Exists so that an
    // unrecognized error still shows up as a visible "!" with a message, instead of being
    // mistaken for one of the specific "not set up on this machine" signals and silently
    // hiding the provider.
    case unexpectedFailure(String)

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
        case .unexpectedFailure(let detail): return "Unexpected error: \(detail)"
        }
    }
}
