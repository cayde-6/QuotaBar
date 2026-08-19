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
    @ViewBuilder
    private var providerCardsRow: some View {
        let cards = HStack(alignment: .top, spacing: 10) {
            ProviderCard(provider: .codex, state: store.codex)
            ProviderCard(provider: .claude, state: store.claude)
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
