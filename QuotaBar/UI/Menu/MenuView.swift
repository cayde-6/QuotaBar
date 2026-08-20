import SwiftUI

/// The popover content shown when the status bar item is clicked.
struct MenuView: View {
    let store: QuotaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providerCardsRow
            MenuFooter(store: store)
        }
        .padding(12)
        .frame(width: 400)
    }

    /// Both cards side by side, wrapped in a single glass container on macOS 26+ so the
    /// two glass surfaces are computed together (consistent lensing/merging at the
    /// boundary) rather than as two independent effects. `.top`-aligned so a short card
    /// (e.g. one showing only an error message) doesn't stretch or center its content —
    /// see the `maxHeight: .infinity` frame on providerCard, which is what actually makes
    /// both cards match the taller one's height.
    ///
    /// A provider that isn't set up on this machine (see `ProviderState.isMissing`) is
    /// dropped from the row entirely — its card doesn't render at all, and the remaining
    /// card fills the row via its own `maxWidth: .infinity` frame. When both are missing,
    /// a single-line placeholder message takes the row's place instead.
    @ViewBuilder
    private var providerCardsRow: some View {
        let codexMissing = store.codex.isMissing(for: .codex)
        let claudeMissing = store.claude.isMissing(for: .claude)

        let cards = HStack(alignment: .top, spacing: 10) {
            if codexMissing && claudeMissing {
                Text("No Claude Code or Codex found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassCard()
            } else {
                if !codexMissing {
                    ProviderCard(provider: .codex, state: store.codex)
                }
                if !claudeMissing {
                    ProviderCard(provider: .claude, state: store.claude)
                }
            }
        }

        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                cards
            }
        } else {
            cards
        }
    }
}
