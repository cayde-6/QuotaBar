import Foundation
import Testing

@Suite("Provider selection")
struct ProviderSelectionTests {
    @Test("defaults to both providers and preserves an explicitly empty selection")
    func persistence() {
        let suiteName = "QuotaBar.ProviderSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ProviderSelection.load(from: defaults) == Set(QuotaProvider.allCases))

        ProviderSelection.save([.codex], to: defaults)
        #expect(ProviderSelection.load(from: defaults) == [.codex])

        ProviderSelection.save([], to: defaults)
        #expect(ProviderSelection.load(from: defaults).isEmpty)

        defaults.set(["unknown-provider"], forKey: "enabledProviders")
        #expect(ProviderSelection.load(from: defaults) == Set(QuotaProvider.allCases))
    }

    @Test("only enabled and set-up providers are visible")
    func visibility() {
        let available = ProviderState()
        var missingCodex = ProviderState()
        missingCodex.lastError = .cliNotFound
        var throttledClaude = ProviderState()
        throttledClaude.lastError = .rateLimited

        #expect(ProviderSelection.visibleProviders(enabled: [.codex, .claude], codex: available, claude: throttledClaude) == [.codex, .claude])
        #expect(ProviderSelection.visibleProviders(enabled: [.codex], codex: available, claude: throttledClaude) == [.codex])
        #expect(ProviderSelection.visibleProviders(enabled: [], codex: available, claude: throttledClaude).isEmpty)
        #expect(ProviderSelection.visibleProviders(enabled: [.codex, .claude], codex: missingCodex, claude: throttledClaude) == [.claude])
    }
}
