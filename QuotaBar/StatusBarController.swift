import AppKit
import SwiftUI

/// Owns the NSStatusItem, its rendered image, and the click-to-open popover.
/// The status bar image is rasterized from SwiftUI via ImageRenderer rather than hosting
/// a live SwiftUI view directly — a hosting view's text doesn't invert when the button is
/// highlighted with the popover open, while a rendered NSImage is unaffected by that.
/// The image carries real color (quota-level indication), so it is no longer a template
/// image — light/dark adaptation is done by hand in `render()` instead.
@MainActor
final class StatusBarController: NSObject {
    private let store: QuotaStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var appearanceObservation: NSKeyValueObservation?

    init(store: QuotaStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let popover = NSPopover()
        popover.behavior = .transient // closes automatically on an outside click
        popover.animates = false
        self.popover = popover

        super.init()

        // See makeContentViewController() — this is also reassigned before every
        // subsequent show, not just set once here.
        popover.contentViewController = makeContentViewController()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))

            // The menu bar's effective appearance can differ from the app's own, and can
            // change for reasons a system theme switch doesn't cover — e.g. changing the
            // desktop wallpaper alone can flip it between light and dark without posting
            // any theme-change notification. Observing the button's own effectiveAppearance
            // catches every case that actually changes what render() needs to draw.
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                // KVO for AppKit UI properties normally fires on the main thread, but
                // `assumeIsolated` would abort the whole process if that assumption were
                // ever wrong — too expensive a way to be wrong for a background utility.
                // Hopping via Task is safe either way, at the cost of a redraw landing one
                // runloop turn later.
                Task { @MainActor in
                    self?.render()
                }
            }
        }

        store.onUpdate = { [weak self] in
            self?.render()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        render()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // NSPopover reuses the same contentViewController across show/close cycles
            // without tearing its view down — SwiftUI's onAppear only fires once, ever —
            // so a fresh hosting controller is needed on every open, or state read into
            // MenuView's @State (e.g. the Launch at Login toggle) would go stale until
            // the app restarts.
            popover.contentViewController = makeContentViewController()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func handleScreenParametersChange() {
        render()
    }

    private func makeContentViewController() -> NSHostingController<MenuView> {
        let hosting = NSHostingController(rootView: MenuView(store: store))
        // Without this, NSHostingController reports its size only AFTER the popover has
        // already been positioned. AppKit's origin is bottom-left, so the popover then
        // grows upward to fit, pushing its top off the top of the screen. Forcing the
        // size to be known up front (from SwiftUI's own preferred content size) fixes
        // the positioning instead of the growth.
        hosting.sizingOptions = [.preferredContentSize]
        return hosting
    }

    private func render() {
        // Determine dark/light from the status item's own effective appearance, not
        // NSApp's — the menu bar can be in a different appearance than the app.
        let isDark = statusItem.button?.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        let view = StatusBarView(codex: store.codex, claude: store.claude, isDark: isDark)
        let renderer = ImageRenderer(content: view)
        // NSScreen.main isn't necessarily the screen the menu bar item is actually on
        // (e.g. retina + non-retina external display) — prefer the button's own screen.
        renderer.scale = statusItem.button?.window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2

        guard let image = renderer.nsImage else { return }
        // No longer a template image: quota-level colors need to survive rendering,
        // and a template image would be reduced to an alpha-only mask.
        image.isTemplate = false
        statusItem.button?.image = image
    }
}
