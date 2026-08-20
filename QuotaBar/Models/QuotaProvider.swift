enum QuotaProvider: String, Sendable, CaseIterable {
    case codex, claude

    var displayName: String { self == .codex ? "CODEX" : "CLAUDE" }

    /// Name of the asset catalog image for this provider's mark.
    var iconName: String { self == .codex ? "CodexMark" : "ClaudeMark" }

    /// True when `error` means "this provider isn't set up on this machine at all",
    /// as opposed to a transient failure (network, keychain prompt, expired token, ...).
    ///
    /// The two providers signal "not installed" differently, hence the asymmetry:
    /// - Codex CLI reports `.cliNotFound` when the binary itself is missing, distinct
    ///   from `.notAuthenticated` (installed but not logged in).
    /// - Claude has no separate "not installed" signal — `.notAuthenticated` is raised
    ///   exactly when neither `~/.claude/.credentials.json` nor a Keychain entry exists,
    ///   which for Claude *is* "not set up on this machine".
    func indicatesMissingSetup(_ error: QuotaError) -> Bool {
        switch self {
        case .codex: return error == .cliNotFound
        case .claude: return error == .notAuthenticated
        }
    }
}
