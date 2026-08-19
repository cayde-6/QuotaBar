import SwiftUI

/// Renders the compact two-provider readout shown in the menu bar itself.
/// This view is never displayed directly — it is rasterized into an NSImage by
/// StatusBarController. That image is no longer a template (it carries quota-level
/// color), so `isDark` is passed in explicitly and every color here is a concrete,
/// precomputed value — dynamic system colors aren't reliable inside ImageRenderer,
/// which renders outside of any window's appearance context.
struct StatusBarView: View {
    let codex: ProviderState
    let claude: ProviderState
    let isDark: Bool

    private var palette: StatusBarPalette { StatusBarPalette(isDark: isDark) }

    var body: some View {
        HStack(spacing: 7) {
            providerBlock(.codex, state: codex)
            providerBlock(.claude, state: claude)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .fixedSize()
    }

    @ViewBuilder
    private func providerBlock(_ provider: QuotaProvider, state: ProviderState) -> some View {
        HStack(spacing: 3) {
            HStack(spacing: 1) {
                Image(provider.iconName)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(palette.neutralColor)

                if hasProblem(state) {
                    Text("!")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.neutralColor)
                }
            }

            // Explicit fixed row heights (rather than the font's natural line height)
            // keep glyphs like "—" from overlapping the row below when spacing is tight.
            VStack(alignment: .trailing, spacing: 0) {
                Text(percentText(state.quota?.shortWindow))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(palette.percentColor(state.quota?.shortWindow))
                    .frame(height: 9, alignment: .center)
                Text(percentText(state.quota?.weeklyWindow))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(palette.percentColor(state.quota?.weeklyWindow))
                    .frame(height: 9, alignment: .center)
            }
        }
    }

    /// True when the icon should carry a "!" — either the last attempt failed,
    /// or the data on screen is old enough to no longer be trustworthy.
    private func hasProblem(_ state: ProviderState) -> Bool {
        state.lastError != nil || state.isStale
    }

    private func percentText(_ window: QuotaWindow?) -> String {
        guard let window else { return "—" }
        return "\(window.displayedPercent)%"
    }
}
