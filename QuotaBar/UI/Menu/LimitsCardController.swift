import AppKit
import SwiftUI

private let cardCornerRadius: CGFloat = 16
private let cardEdgeGap: CGFloat = 2
private let cardPointerBase: CGFloat = 26
private let cardPointerDepth: CGFloat = 11

/// Owns the floating dark "limits card" panel the rail widget opens instead of
/// MenuPopoverController's NSPopover. NSPopover paints its own arrow via a system frame
/// view that can't be recolored (verified: setting the popover window's backgroundColor
/// has no effect on it), and that gray arrow stands out against the widget's black
/// chrome — so the rail path gets its own borderless panel with no arrow at all. The
/// status bar item keeps using MenuPopoverController, arrow and all.
@MainActor
final class LimitsCardController {
    private let store: QuotaStore
    private let onOpenSettings: () -> Void

    private var panel: LimitsCardPanel?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var monitorsInstalled = false

    init(store: QuotaStore, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenSettings = onOpenSettings
    }

    deinit {
        MainActor.assumeIsolated {
            removeMonitors()
        }
    }

    var isShown: Bool { panel?.isVisible ?? false }

    func show(anchoredTo anchorFrame: NSRect, edge: RailEdge, on screen: NSScreen) {
        // NSHostingView doesn't tear its view down between shows any more than
        // NSPopover's contentViewController does — SwiftUI's own state (e.g. MenuView's
        // Launch at Login toggle) would go stale until the app restarts otherwise. See
        // MenuPopoverController.makeContentViewController for the same reasoning.
        let openSettings = { [weak self] in
            self?.close()
            self?.onOpenSettings()
        }
        // Built with pointerOffset 0 first: the offset depends on the frame, and the frame
        // depends on this view's fittingSize, so the real offset isn't known yet. Measured
        // below, then the view is rebuilt with it — the offset doesn't affect fittingSize
        // (it only slides the pointer along a side, not the card's overall size), so this
        // first measurement stays valid and doesn't need to be taken again.
        let hostingView = NSHostingView(rootView: CardContent(store: store, edge: edge, pointerOffset: 0, onOpenSettings: openSettings))

        let size = hostingView.fittingSize
        hostingView.frame = CGRect(origin: .zero, size: size)

        let panel = self.panel ?? LimitsCardPanel()
        panel.contentView = hostingView
        self.panel = panel

        let (cardFrame, pointerOffset) = frame(size: size, anchorFrame: anchorFrame, edge: edge, screen: screen)
        hostingView.rootView = CardContent(store: store, edge: edge, pointerOffset: pointerOffset, onOpenSettings: openSettings)
        panel.setFrame(cardFrame, display: true)
        panel.orderFrontRegardless()

        installMonitorsIfNeeded()
    }

    func close() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    /// The card sits with a 2pt gap on whichever side of the rail is free, centered on
    /// the rail along the perpendicular axis, then clamped so it never runs off `screen`.
    /// The gap is small because the card's own pointer (see CardShape) already supplies
    /// the visual separation from the rail; a wider gap would leave the pointer's tip
    /// floating in empty space instead of touching it.
    ///
    /// Clamping can shift the card's body off-center from the rail (rail parked at the
    /// very top/bottom of the screen, or — for `.bottom` — at the very left/right). The
    /// returned `pointerOffset` slides the pointer back along its side by exactly that
    /// shift, so its tip still points at the rail's center even though the body doesn't.
    private func frame(size: CGSize, anchorFrame: NSRect, edge: RailEdge, screen: NSScreen) -> (frame: CGRect, pointerOffset: CGFloat) {
        var origin: CGPoint
        switch edge {
        case .right:
            origin = CGPoint(x: anchorFrame.minX - cardEdgeGap - size.width, y: anchorFrame.midY - size.height / 2)
        case .left:
            origin = CGPoint(x: anchorFrame.maxX + cardEdgeGap, y: anchorFrame.midY - size.height / 2)
        case .bottom:
            origin = CGPoint(x: anchorFrame.midX - size.width / 2, y: anchorFrame.maxY + cardEdgeGap)
        }
        let idealOrigin = origin

        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))

        // The pointer lives in the card's own view coordinates, which run top-left-down —
        // the opposite sense from AppKit's bottom-left-up screen coordinates on the
        // vertical axis. So a clamp that raises the card on screen (larger y) must lower
        // the pointer within it (positive offset) to keep pointing at the same screen
        // point, hence the sign flip on `.left`/`.right` but not on `.bottom`, where both
        // axes already agree.
        let pointerOffset: CGFloat
        switch edge {
        case .left, .right:
            pointerOffset = origin.y - idealOrigin.y
        case .bottom:
            pointerOffset = idealOrigin.x - origin.x
        }

        return (CGRect(origin: origin, size: size), pointerOffset)
    }

    /// Stands in for what NSPopover's `.transient` behavior did for free: closing on an
    /// outside click or Escape. Guarded so a second `show()` while the card is already up
    /// doesn't install a duplicate set — they're only ever torn down in `close()`/`deinit`.
    private func installMonitorsIfNeeded() {
        guard !monitorsInstalled else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }

        // Never swallows the event — a click on the rail panel itself must still reach
        // RailInteractionView so it can register as a click there too.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.window !== self?.panel {
                Task { @MainActor in self?.close() }
            }
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Escape
            // Only swallow Escape when there's no key window at all, or the key window is
            // the card's own panel. If some other window is key (e.g. Settings), Escape
            // must reach it untouched instead of being eaten here first.
            guard NSApp.keyWindow == nil || NSApp.keyWindow === self?.panel else { return event }
            Task { @MainActor in self?.close() }
            return nil
        }

        monitorsInstalled = true
    }

    private func removeMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        localKeyMonitor = nil
        monitorsInstalled = false
    }
}

/// MenuView dressed up as a floating card: `.dark` already fills its own black
/// background, but that only covers MenuView's own frame, not the extra padding this
/// adds to keep content off the pointer — so the card supplies its own black fill,
/// clipped and stroked with the same CardShape (pointer included) so all three line up.
private struct CardContent: View {
    let store: QuotaStore
    let edge: RailEdge
    let pointerOffset: CGFloat
    let onOpenSettings: () -> Void

    var body: some View {
        let shape = CardShape(pointerEdge: edge, cornerRadius: cardCornerRadius, pointerBase: cardPointerBase, pointerDepth: cardPointerDepth, pointerOffset: pointerOffset)

        MenuView(store: store, style: .dark, onOpenSettings: onOpenSettings)
            .padding(pointerEdge, cardPointerDepth)
            .background(shape.fill(Color.black))
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            // Pins leading/trailing to always mean left/right, regardless of the system
            // locale's layout direction — CardShape draws the pointer at absolute
            // minX/maxX, so an RTL flip of `.padding(pointerEdge, ...)` above would put
            // the padding on the opposite side from the pointer it's meant to clear.
            .environment(\.layoutDirection, .leftToRight)
    }

    /// Keeps content off the pointer poking out of `edge` — otherwise it would render
    /// on top of the triangle instead of stopping at the card body's edge.
    private var pointerEdge: Edge.Set {
        switch edge {
        case .right: return .trailing
        case .left: return .leading
        case .bottom: return .bottom
        }
    }
}
