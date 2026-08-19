/// One provider's quota source. `allowInteraction` is only meaningful for providers
/// that may need to prompt the user (Claude's Keychain read); providers that never
/// prompt ignore it.
protocol QuotaProviding: Sendable {
    func fetch(allowInteraction: Bool) async throws -> ProviderQuota
}
