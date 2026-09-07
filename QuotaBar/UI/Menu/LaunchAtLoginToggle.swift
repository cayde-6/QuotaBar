import SwiftUI

/// The "Launch at Login" switch. Unlabeled: it sits inside a settings-form row that
/// already supplies the icon and title, so this view contributes only the control.
struct LaunchAtLoginToggle: View {
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled

    var body: some View {
        Toggle("", isOn: $launchAtLoginEnabled)
            .labelsHidden()
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
                // Unlike the popover's MenuView (rebuilt fresh on every open), the
                // settings window is created once and reused (see
                // `SettingsWindowController.isReleasedWhenClosed`), so this view's state
                // isn't reset on every open — this only re-reads reality the first time
                // the window is shown. Changes made outside QuotaBar while the window is
                // already open (e.g. in System Settings) won't be picked up until it's
                // recreated, which currently never happens after the first show.
                launchAtLoginEnabled = LaunchAtLogin.isEnabled
            }
    }
}
