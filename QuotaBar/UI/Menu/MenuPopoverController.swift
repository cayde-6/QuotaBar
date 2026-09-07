import AppKit
import SwiftUI

/// Owns the single NSPopover that shows MenuView, so the status bar item and the rail
/// panel both open the exact same popover content instead of each keeping their own.
@MainActor
final class MenuPopoverController {
    private let store: QuotaStore
    private let popover: NSPopover
    private let onOpenSettings: () -> Void

    init(store: QuotaStore, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenSettings = onOpenSettings

        let popover = NSPopover()
        popover.behavior = .transient // closes automatically on an outside click
        popover.animates = false
        self.popover = popover

        // See makeContentViewController() — this is also reassigned before every
        // subsequent show, not just set once here. .system here is just a harmless
        // initial value; it's replaced with the real style before the first show.
        popover.contentViewController = makeContentViewController(style: .system)
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge, style: MenuStyle) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show(relativeTo: rect, of: view, preferredEdge: preferredEdge, style: style)
        }
    }

    /// Unconditional open, split out from `toggle(relativeTo:of:preferredEdge:style:)` so
    /// that method can separate "decide whether to open or close" from "actually open" —
    /// internal helper only, `toggle` is the sole caller.
    private func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge, style: MenuStyle) {
        // NSPopover reuses the same contentViewController across show/close cycles
        // without tearing its view down — SwiftUI's onAppear only fires once, ever —
        // so a fresh hosting controller is needed on every open, or state read into
        // MenuView's @State (e.g. the Launch at Login toggle) would go stale until
        // the app restarts.
        popover.contentViewController = makeContentViewController(style: style)
        // Also colors the popover's own frame and arrow, but more importantly forces
        // SwiftUI inside the hosting controller into the dark color scheme, so
        // .primary/.secondary in the cards flip on their own — no manual recoloring.
        popover.appearance = style == .dark ? NSAppearance(named: .darkAqua) : nil
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
    }

    func close() {
        popover.performClose(nil)
    }

    private func makeContentViewController(style: MenuStyle) -> NSHostingController<MenuView> {
        // Closes the popover first: the settings window is about to steal focus anyway,
        // which would collapse a `.transient` popover on its own, but doing it explicitly
        // here keeps `isShown` honest rather than relying on that side effect.
        let openSettings = { [weak self] in
            self?.close()
            self?.onOpenSettings()
        }
        let hosting = NSHostingController(rootView: MenuView(store: store, style: style, onOpenSettings: openSettings))
        // Without this, NSHostingController reports its size only AFTER the popover has
        // already been positioned. AppKit's origin is bottom-left, so the popover then
        // grows upward to fit, pushing its top off the top of the screen. Forcing the
        // size to be known up front (from SwiftUI's own preferred content size) fixes
        // the positioning instead of the growth.
        hosting.sizingOptions = [.preferredContentSize]
        return hosting
    }
}
