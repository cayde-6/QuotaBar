import SwiftUI

/// Both footer rows, on their own material backing so they stay legible over any
/// desktop wallpaper — unlike the provider cards, which have their own glass/material
/// background per card, the footer has no such backing of its own by default, and a
/// popover this translucent otherwise leaves plain text sitting directly on the
/// desktop image behind it.
struct MenuFooter: View {
    let store: QuotaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // .secondary is inherently semi-transparent, so it picks up a cast from
                // whatever is behind it — including the footer's own material, which is
                // itself a blurred, tinted sample of the desktop behind the window. On
                // saturated wallpaper this reads as a color tint, not neutral gray, no
                // matter how dense the material is. .primary is opaque and immune to
                // that; the smaller size keeps it from looking heavier than its neighbors.
                Text(DateFormatting.lastUpdatedText(store.lastSuccessfulUpdate))
                    .font(.system(size: 9))
                    .foregroundStyle(.primary)

                Spacer()

                // Not disabled while refreshing: refresh() is idempotent (it skips any
                // provider that already has a request in flight), and one provider being
                // stuck should never block a manual retry of the other. userInitiated:
                // true because this is a deliberate click — the one other case allowed
                // to prompt for Keychain access if Claude's credential item needs it.
                Button(store.isRefreshing ? "Refreshing…" : "Refresh") {
                    store.refresh(userInitiated: true)
                }
                .glassButton()
                // Plain glass buttons render their label in a washed-out secondary-ish
                // tone that's nearly invisible on light glass — force real contrast.
                .foregroundStyle(.primary)

                Picker("Refresh every", selection: Binding(
                    get: { store.refreshIntervalMinutes },
                    set: { store.refreshIntervalMinutes = $0 }
                )) {
                    ForEach(QuotaStore.validRefreshIntervalsMinutes, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden() // the "Refresh" button right next to it already says what this is for
                .font(.system(size: 11))
                .frame(width: 110)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    LaunchAtLoginToggle()

                    Spacer()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .glassButton()
                    // Plain (non-prominent) glass buttons render their label in a
                    // washed-out secondary-ish tone that's nearly invisible on light
                    // glass — force it to a real, theme-adapting contrast color instead.
                    .foregroundStyle(.primary)
                }

                if LaunchAtLogin.status == .requiresApproval {
                    // .primary, not .secondary — same reasoning as "Updated" above: this
                    // sits on the same translucent footer material.
                    Text("Approve in System Settings → Login Items")
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(10)
        // .regularMaterial was still translucent enough that a saturated desktop
        // background bled its color into supposedly-neutral secondary text (e.g. "Updated
        // HH:mm" reading blue against blue wallpaper) — .thickMaterial is denser and
        // keeps text color independent of whatever is behind the popover. This only
        // affects the footer's own backing; the provider cards' glass is untouched.
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
