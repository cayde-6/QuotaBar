enum QuotaProvider: String, Sendable, CaseIterable {
    case codex, claude

    var displayName: String { self == .codex ? "CODEX" : "CLAUDE" }

    /// Name of the asset catalog image for this provider's mark.
    var iconName: String { self == .codex ? "CodexMark" : "ClaudeMark" }
}
