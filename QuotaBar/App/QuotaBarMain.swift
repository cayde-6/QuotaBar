import AppKit
import Darwin

/// Pure AppKit entry point — no SwiftUI App/Scene, since a Scene would create windows
/// and a default menu that this menu-bar-only utility must never show.
@main
enum QuotaBarMain {
    static func main() {
        // Without this, writing to codex app-server's stdin after it has already exited
        // delivers SIGPIPE and kills QuotaBar outright — FileHandle.write(contentsOf:)
        // does not surface that as a Swift error. Ignoring the signal turns it into a
        // normal EPIPE thrown from write(), which CodexQuotaProvider already handles.
        signal(SIGPIPE, SIG_IGN)

        // Keychain interaction is off by default for the whole process. Claude Code
        // rewrites its own credential item whenever it refreshes its OAuth token, which
        // resets any "Always Allow" the user previously granted — so a background
        // refresh could otherwise pop up a system access-request dialog at any time,
        // unprompted. ClaudeQuotaProvider.fetch(allowInteraction:) is the only place that
        // ever turns this back on, and only for the two refreshes a user actually asked
        // for (first launch, manual Refresh).
        setKeychainInteractionAllowed(false)

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon, no app switcher entry
        app.run()
    }
}
