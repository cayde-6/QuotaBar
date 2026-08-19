import SwiftUI

/// The popover content shown when the status bar item is clicked.
struct MenuView: View {
    let store: QuotaStore

    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providerCardsRow
            footer
        }
        .padding(12)
        .frame(width: 400)
    }

    // MARK: - Footer

    /// Both footer rows, on their own material backing so they stay legible over any
    /// desktop wallpaper — unlike the provider cards, which have their own glass/material
    /// background per card, the footer has no such backing of its own by default, and a
    /// popover this translucent otherwise leaves plain text sitting directly on the
    /// desktop image behind it.
    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // .secondary is inherently semi-transparent, so it picks up a cast from
                // whatever is behind it — including the footer's own material, which is
                // itself a blurred, tinted sample of the desktop behind the window. On
                // saturated wallpaper this reads as a color tint, not neutral gray, no
                // matter how dense the material is. .primary is opaque and immune to
                // that; the smaller size keeps it from looking heavier than its neighbors.
                Text(lastUpdatedText)
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
                    Toggle(isOn: $launchAtLoginEnabled) {
                        Text("Launch at Login")
                            .font(.system(size: 11)) // matches the rest of the footer's captions
                    }
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        // Guard against the resync below (or .onAppear) re-triggering
                        // this: if the toggle already matches reality, there's
                        // nothing to change — this also stops the "requiresApproval
                        // snaps back to off" resync from turning into a spurious
                        // unregister() call.
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                        } catch {
                            // Ignored — the resync below reflects whatever actually took effect.
                        }
                        launchAtLoginEnabled = LaunchAtLogin.isEnabled
                    }
                    .onAppear {
                        // StatusBarController hands the popover a fresh hosting
                        // controller (and therefore a fresh MenuView) before every
                        // show, so this fires on every open and reliably picks up
                        // changes made outside QuotaBar (e.g. in System Settings).
                        launchAtLoginEnabled = LaunchAtLogin.isEnabled
                    }

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

    // MARK: - Provider cards

    /// Both cards side by side, wrapped in a single glass container on macOS 26+ so the
    /// two glass surfaces are computed together (consistent lensing/merging at the
    /// boundary) rather than as two independent effects. `.top`-aligned so a short card
    /// (e.g. one showing only an error message) doesn't stretch or center its content —
    /// see the `maxHeight: .infinity` frame on providerCard, which is what actually makes
    /// both cards match the taller one's height.
    @ViewBuilder
    private var providerCardsRow: some View {
        let cards = HStack(alignment: .top, spacing: 10) {
            providerCard(.codex, state: store.codex)
            providerCard(.claude, state: store.claude)
        }

        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                cards
            }
        } else {
            cards
        }
    }

    @ViewBuilder
    private func providerCard(_ provider: QuotaProvider, state: ProviderState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(iconName(for: provider))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.secondary)

                Text(provider.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if state.quota == nil, let error = state.lastError {
                // Wraps instead of truncating or growing the card — card width is fixed
                // by the equal-width HStack above, not by this text's content.
                Text(error.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let warning = warningText(for: state) {
                    Text("⚠︎ \(warning)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 12) {
                    windowColumn(title: "5 HOUR", window: state.quota?.shortWindow)
                    windowColumn(title: "WEEKLY", window: state.quota?.weeklyWindow)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }

    @ViewBuilder
    private func windowColumn(title: String, window: QuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            if let window {
                Text("\(window.displayedPercent)%")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color(for: window.level))
                if let resetText = resetDescription(for: window.resetsAt) {
                    Text(resetText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No data")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconName(for provider: QuotaProvider) -> String {
        provider == .codex ? "CodexMark" : "ClaudeMark"
    }

    /// `.yellow` reads poorly as text color in both themes, so warning uses `.orange`
    /// instead — same "not healthy, not critical" meaning, actually legible.
    private func color(for level: QuotaLevel) -> Color {
        switch level {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    /// Message shown above a provider's window columns when the data is present but
    /// suspect (stale or the last refresh attempt failed).
    private func warningText(for state: ProviderState) -> String? {
        guard state.quota != nil else { return nil }
        if let error = state.lastError { return error.message }
        if state.isStale { return "Data is stale" }
        return nil
    }

    // MARK: - Formatting

    private var lastUpdatedText: String {
        guard let date = store.lastSuccessfulUpdate else { return "Updated never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: date))"
    }

    /// Shortened for the narrower card columns: no "Resets" prefix (the heading above it
    /// already says which window), and a short weekday ("Sat 03:00" instead of
    /// "Resets Saturday 14:00").
    private func resetDescription(for date: Date?) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return nil }

        if interval < 24 * 3600 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return formatter.string(from: date)
    }
}

// MARK: - Liquid Glass helpers

/// Card background: real Liquid Glass on macOS 26+, a plain system material otherwise.
/// One modifier instead of an `#available` branch at every card, and neutral either way
/// — no level-color tinting, color lives only in the percentage text.
private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content.background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// Glass button chrome on macOS 26+; the system default style otherwise.
private struct GlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content
        }
    }
}

private extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }

    func glassButton() -> some View {
        modifier(GlassButton())
    }
}
