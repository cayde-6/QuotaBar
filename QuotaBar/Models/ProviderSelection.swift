import Foundation

/// Keeps the user's provider choices separate from whether a provider is set up
/// on this Mac. An absent preference means both providers stay enabled after an
/// upgrade; an explicitly saved empty array means neither is enabled.
enum ProviderSelection {
    private static let defaultsKey = "enabledProviders"

    static func load(from defaults: UserDefaults) -> Set<QuotaProvider> {
        guard let stored = defaults.stringArray(forKey: defaultsKey) else {
            return Set(QuotaProvider.allCases)
        }
        let enabled = Set(stored.compactMap(QuotaProvider.init(rawValue:)))
        return enabled.isEmpty && !stored.isEmpty ? Set(QuotaProvider.allCases) : enabled
    }

    static func save(_ enabled: Set<QuotaProvider>, to defaults: UserDefaults) {
        defaults.set(enabled.map(\.rawValue).sorted(), forKey: defaultsKey)
    }

    static func visibleProviders(
        enabled: Set<QuotaProvider>,
        codex: ProviderState,
        claude: ProviderState
    ) -> [QuotaProvider] {
        QuotaProvider.allCases.filter { provider in
            guard enabled.contains(provider) else { return false }
            let state = provider == .codex ? codex : claude
            return !state.isMissing(for: provider)
        }
    }
}
