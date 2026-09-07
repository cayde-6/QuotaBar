import AppKit
import SwiftUI

/// Owns the single settings window, created lazily on first `show()`.
@MainActor
final class SettingsWindowController {
    private let store: QuotaStore
    private var window: NSWindow?
    private var keyDownMonitor: Any?

    init(store: QuotaStore) {
        self.store = store
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    func show() {
        let window = ensureWindow()
        installKeyDownMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // `activate(ignoringOtherApps:)` from a background accessory app is only a request —
        // macOS 14+ is free to ignore it, leaving the window behind the frontmost app. Forcing
        // the window itself to the front is what actually guarantees visibility.
        window.orderFrontRegardless()
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        let hosting = NSHostingController(rootView: SettingsView(store: store))
        // Sizes the window to the view's own preferred content size instead of an
        // arbitrary NSWindow default, matching the popover's use of the same option.
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "QuotaBar Settings"
        // This is an accessory app with no Dock icon and no main menu, so there's no
        // Window menu / Cmd-W and no default Escape-closes-window handling either — both
        // have to be wired up by hand below. Keeping the window alive when closed (rather
        // than deallocating it) means `show()` can reuse the same instance instead of
        // rebuilding it, and reset its content, every time.
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )

        return window
    }

    /// Closes the window on Escape or Cmd-W while it's key. Needed only because this
    /// accessory app has no main menu to supply the usual Cmd-W item or Escape-cancels
    /// behavior for free — a normal windowed app gets both without any of this.
    ///
    /// Called from `show()` rather than `ensureWindow()`: the window survives close (see
    /// `isReleasedWhenClosed` above) but `windowWillClose` tears the monitor down each time,
    /// so it must be reinstalled on every reopen, not just the first. Idempotent via the
    /// `keyDownMonitor != nil` guard since `show()` also runs on an already-visible window.
    private func installKeyDownMonitor() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }

            let isEscape = event.keyCode == 53 // kVK_Escape
            let isCommandW = event.charactersIgnoringModifiers == "w" && event.modifierFlags.contains(.command)
            if isEscape || isCommandW {
                window.performClose(nil)
                return nil
            }
            return event
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        keyDownMonitor = nil
    }
}
