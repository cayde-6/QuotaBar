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
                Image(iconName(for: provider))
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(neutralColor)

                if hasProblem(state) {
                    Text("!")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(neutralColor)
                }
            }

            // Explicit fixed row heights (rather than the font's natural line height)
            // keep glyphs like "—" from overlapping the row below when spacing is tight.
            VStack(alignment: .trailing, spacing: 0) {
                Text(percentText(state.quota?.shortWindow))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(percentColor(state.quota?.shortWindow))
                    .frame(height: 9, alignment: .center)
                Text(percentText(state.quota?.weeklyWindow))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(percentColor(state.quota?.weeklyWindow))
                    .frame(height: 9, alignment: .center)
            }
        }
    }

    /// True when the icon should carry a "!" — either the last attempt failed,
    /// or the data on screen is old enough to no longer be trustworthy.
    private func hasProblem(_ state: ProviderState) -> Bool {
        state.lastError != nil || state.isStale
    }

    private func iconName(for provider: QuotaProvider) -> String {
        provider == .codex ? "CodexMark" : "ClaudeMark"
    }

    private func percentText(_ window: QuotaWindow?) -> String {
        guard let window else { return "—" }
        return "\(window.displayedPercent)%"
    }

    // MARK: - Colors

    /// Icon, "!", and the "—" placeholder aren't level-colored — they read as plain
    /// foreground content, matching a template image's usual look.
    private var neutralColor: Color {
        isDark ? .white : .black
    }

    private func percentColor(_ window: QuotaWindow?) -> Color {
        guard let window else { return neutralColor }
        return color(for: window.level)
    }

    /// Two hand-picked shades per level — one for the near-black dark menu bar, one for
    /// the light one. A straight system green/yellow/red would look identical in both,
    /// which reads fine on dark but is nearly invisible (yellow) or low-contrast
    /// (green/red) against a light menu bar, so the light variants are darker/more
    /// saturated on purpose.
    private func color(for level: QuotaLevel) -> Color {
        switch level {
        case .healthy:
            return isDark
                ? Color(red: 0.20, green: 0.85, blue: 0.35)
                : Color(red: 0.00, green: 0.50, blue: 0.15)
        case .warning:
            return isDark
                ? Color(red: 1.00, green: 0.80, blue: 0.10)
                : Color(red: 0.55, green: 0.40, blue: 0.00)
        case .critical:
            return isDark
                ? Color(red: 1.00, green: 0.30, blue: 0.30)
                : Color(red: 0.75, green: 0.05, blue: 0.05)
        }
    }
}
