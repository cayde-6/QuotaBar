import SwiftUI

/// The popover content shown when the status bar item is clicked. Limits only — every
/// other setting (surface mode, refresh interval, launch at login, update notice, Quit)
/// lives in the separate settings window, opened via the gear button below.
struct MenuView: View {
    let store: QuotaStore
    let style: MenuStyle
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providerCardsRow
            statusRow
        }
        .padding(12)
        .frame(width: 400)
        // Only added for the rail widget: the popover otherwise stays exactly as it was,
        // and a light/glass background here would fight the widget's own black chrome.
        // Fully opaque, not just dark: this view lives in LimitsCardPanel, a transparent
        // borderless window with no system material or blur behind it (unlike NSPopover,
        // which has its own opaque backing) — any opacity here lets whatever window is
        // behind it show through and bleed into the card's text.
        .background(style == .dark ? Color.black : nil)
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
                let placeholder = Text("No Claude Code or Codex found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)

                // Glass/material is light — swap it for a dark fill to match the rail
                // widget's black chrome; the system popover keeps its glass as-is.
                if style == .dark {
                    placeholder.background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    placeholder.glassCard()
                }
            } else {
                if !codexMissing {
                    ProviderCard(provider: .codex, state: store.codex, style: style)
                }
                if !claudeMissing {
                    ProviderCard(provider: .claude, state: store.claude, style: style)
                }
            }
        }

        // GlassEffectContainer is only meaningful when the cards inside it are actually
        // glass — the dark rail style replaces that glass with a flat fill, so there's
        // nothing for it to lens/merge, and it's skipped entirely.
        if style == .system, #available(macOS 26.0, *) {
            GlassEffectContainer {
                cards
            }
        } else {
            cards
        }
    }

    /// "Updated HH:mm" plus Refresh and the gear that opens settings, on its own material
    /// backing so it stays legible over any desktop wallpaper — unlike the provider cards,
    /// which have their own glass/material background per card, this row has no such
    /// backing of its own by default, and a popover this translucent otherwise leaves
    /// plain text sitting directly on the desktop image behind it.
    private var statusRow: some View {
        HStack(spacing: 8) {
            // .secondary is inherently semi-transparent, so it picks up a cast from
            // whatever is behind it — including this row's own material, which is itself
            // a blurred, tinted sample of the desktop behind the window. On saturated
            // wallpaper this reads as a color tint, not neutral gray, no matter how dense
            // the material is. .primary is opaque and immune to that; the smaller size
            // keeps it from looking heavier than its neighbors.
            Text(DateFormatting.lastUpdatedText(store.lastSuccessfulUpdate))
                .font(.system(size: 9))
                .foregroundStyle(.primary)

            Spacer()

            // Not disabled while refreshing: refresh() is idempotent (it skips any
            // provider that already has a request in flight), and one provider being
            // stuck should never block a manual retry of the other. userInitiated: true
            // because this is a deliberate click — the one other case allowed to prompt
            // for Keychain access if Claude's credential item needs it.
            Button(store.isRefreshing ? "Refreshing…" : "Refresh") {
                store.refresh(userInitiated: true)
            }
            .glassButton()
            // Plain glass buttons render their label in a washed-out secondary-ish
            // tone that's nearly invisible on light glass — force real contrast.
            .foregroundStyle(.primary)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(10)
        // .regularMaterial was still translucent enough that a saturated desktop
        // background bled its color into supposedly-neutral secondary text (e.g. "Updated
        // HH:mm" reading blue against blue wallpaper) — .thickMaterial is denser and
        // keeps text color independent of whatever is behind the popover. This only
        // affects this row's own backing; the provider cards' glass is untouched.
        // The rail's dark style swaps that material for a flat fill instead — material
        // is designed to pick up a light desktop behind it, which doesn't apply here.
        .background(statusRowBackground)
    }

    @ViewBuilder
    private var statusRowBackground: some View {
        if style == .dark {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07))
        } else {
            RoundedRectangle(cornerRadius: 12).fill(.thickMaterial)
        }
    }
}
