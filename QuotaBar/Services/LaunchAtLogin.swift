import ServiceManagement

/// Thin wrapper over SMAppService for the "Launch at Login" toggle.
/// No separate helper app is registered — QuotaBar registers itself.
enum LaunchAtLogin {
    /// Exposed so callers can tell a plain "off" apart from "registered but the user
    /// hasn't approved it in System Settings yet" (`register()` doesn't throw for that).
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
