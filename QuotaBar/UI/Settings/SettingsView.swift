import SwiftUI

/// Everything that isn't the quota readout itself: provider choice, surface choice,
/// refresh interval, launch-at-login, update notice, and Quit. Shown in its own window (see
/// `SettingsWindowController`) rather than the popover, which is reserved for
/// provider cards.
struct SettingsView: View {
    let store: QuotaStore

    var body: some View {
        Form {
            Section {
                HStack {
                    SettingsRowIcon(systemName: "macwindow.on.rectangle", tint: .blue)
                    Text("Show as")
                    Spacer()
                    Picker("Show as", selection: Binding(
                        get: { store.surfaceMode },
                        set: { store.surfaceMode = $0 }
                    )) {
                        ForEach(SurfaceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Where the quota readout lives. The menu bar item stays visible while the widget has nothing to show.")
            }

            Section {
                ForEach(QuotaProvider.allCases, id: \.self) { provider in
                    Toggle(isOn: Binding(
                        get: { store.isEnabled(provider) },
                        set: { store.setEnabled(provider, to: $0) }
                    )) {
                        HStack(spacing: 8) {
                            Image(provider.iconName)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .foregroundStyle(.secondary)
                            Text(provider.displayName.capitalized)
                        }
                    }
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Hidden providers are not checked. If both are hidden, the menu bar icon stays available for Settings.")
            }

            Section {
                HStack {
                    SettingsRowIcon(systemName: "arrow.clockwise", tint: .green)
                    Text("Refresh every")
                    Spacer()
                    Picker("Refresh every", selection: Binding(
                        get: { store.refreshIntervalMinutes },
                        set: { store.refreshIntervalMinutes = $0 }
                    )) {
                        ForEach(QuotaStore.validRefreshIntervalsMinutes, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            } header: {
                Text("Refreshing")
            } footer: {
                Text("Changing this restarts the timer immediately; it doesn't refresh right away.")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        SettingsRowIcon(systemName: "power", tint: .orange)
                        Text("Launch at Login")
                        Spacer()
                        LaunchAtLoginToggle()
                    }
                    if LaunchAtLogin.status == .requiresApproval {
                        Text("Approve QuotaBar in System Settings → General → Login Items.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 28)
                    }
                }

                if let availableUpdate = store.availableUpdate {
                    HStack {
                        SettingsRowIcon(systemName: "arrow.down.circle", tint: .purple)
                        Text("Update available: \(availableUpdate.version)")
                        Spacer()
                        Button("Download") {
                            NSWorkspace.shared.open(availableUpdate.releaseURL)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Quit QuotaBar") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

/// A row icon matching System Settings: a white SF Symbol on a colored rounded-square
/// background.
private struct SettingsRowIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(tint)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}
