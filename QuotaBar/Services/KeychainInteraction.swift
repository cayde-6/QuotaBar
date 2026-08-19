import Security

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
