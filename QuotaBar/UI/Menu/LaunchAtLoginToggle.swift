import SwiftUI

/// The "Launch at Login" toggle, shown in the footer.
struct LaunchAtLoginToggle: View {
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled

    var body: some View {
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
    }
}
