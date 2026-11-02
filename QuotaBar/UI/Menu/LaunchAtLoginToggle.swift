import SwiftUI
import ServiceManagement

/// The "Launch at Login" switch. Unlabeled: it sits inside a settings-form row that
/// already supplies the icon and title, so this view contributes only the control.
struct LaunchAtLoginToggle: View {
    @Binding var status: SMAppService.Status

    var body: some View {
        Toggle("", isOn: Binding(
            get: { status == .enabled },
            set: { enabled in
                // Only user input writes to the system. Re-reading status on focus
                // must never turn an unapproved registration into an unregister call.
                do {
                    try LaunchAtLogin.setEnabled(enabled)
                } catch {
                    // Reflect whatever actually took effect, including approval pending.
                }
                status = LaunchAtLogin.status
            }
        ))
            .labelsHidden()
            .toggleStyle(.switch)
    }
}
