import AppKit
import SwiftUI

/// Owns the floating rail panel: lazy creation, sizing, positioning, and drag-to-dock.
@MainActor
final class RailPanelController {
    private let store: QuotaStore
    private let card: LimitsCardController

    private var panel: RailPanel?
    private var hostingView: NSHostingView<RailView>?
    private var interactionView: RailInteractionView?
    private var placement: RailPlacement = AppSettings.railPlacement
    private var screenParametersObserver: NSObjectProtocol?

    /// What the surface mode last asked for via `setVisible`. Reapplied whenever
    /// `AppDelegate` notices the visible provider set changed (it owns the one
    /// observation of `store.codex`/`store.claude` — see AppDelegate's
    /// observeProviderVisibility — and calls back into `setVisible`), since whether the
    /// rail actually has anything to show can change independently of the mode itself.
    private var desiredVisible = false

    /// True for the duration of `performDrag(with:)` — from `onDragBegan`, which fires on
    /// every mouseDown including plain clicks, until either `handleClick` or
    /// `handleDragEnded` runs once it returns. Guards `applyVisibility` — see its comment —
    /// against fighting AppKit's own window move with its own `setFrame`.
    private var isDragging = false

    /// Snapshot of `card.isShown` taken on `mouseDown`, not read fresh in `handleClick`.
    /// The card closes itself on `mouseDown` (any mouseDown outside it does — see
    /// LimitsCardController's own monitors) before `RailInteractionView` ever reports the
    /// click on `mouseUp` — by then `card.isShown` is already `false`, and `handleClick`
    /// would read that as "wasn't open" and show it again, turning a close-on-click into a
    /// flicker. Do not replace this with a toggle-style check.
    private var cardWasShownAtMouseDown = false

    init(store: QuotaStore, card: LimitsCardController) {
        self.store = store
        self.card = card

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenParametersChange()
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let screenParametersObserver {
                NotificationCenter.default.removeObserver(screenParametersObserver)
            }
        }
    }

    func setVisible(_ visible: Bool) {
        desiredVisible = visible
        applyVisibility()
    }

    /// Skipped mid-drag: `store.codex`/`store.claude` mutate several times per auto-refresh
    /// cycle (on `.started` and again on `.finished`, for each provider), and any of those
    /// landing while the mouse is down would `setFrame` the panel back to its last saved
    /// placement — or `orderOut` it if the provider list went briefly empty — fighting the
    /// live `setFrameOrigin` calls `RailInteractionView` is making from the drag. Deferred
    /// work isn't lost: `handleDragEnded` calls this again once dragging stops.
    private func applyVisibility() {
        guard !isDragging else { return }

        let providers = RailView.visibleProviders(store: store)
        guard desiredVisible, !providers.isEmpty else {
            panel?.orderOut(nil)
            return
        }

        let panel = ensurePanel()
        resize(panel, providerCount: providers.count)
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> RailPanel {
        if let panel { return panel }

        let panel = RailPanel()
        let hostingView = NSHostingView(rootView: RailView(store: store, edge: placement.edge))
        panel.contentView = hostingView
        self.hostingView = hostingView

        let interactionView = RailInteractionView(frame: hostingView.bounds)
        interactionView.autoresizingMask = [.width, .height]
        interactionView.onClick = { [weak self] in self?.handleClick() }
        interactionView.onMouseDown = { [weak self] in self?.cardWasShownAtMouseDown = self?.card.isShown ?? false }
        interactionView.onDragBegan = { [weak self] in self?.isDragging = true }
        interactionView.onDragEnded = { [weak self] in self?.handleDragEnded() }
        hostingView.addSubview(interactionView)
        self.interactionView = interactionView

        self.panel = panel
        return panel
    }

    /// Rebuilds `RailView`'s root view with the current `placement.edge` so the panel's
    /// corner rounding stays in sync after a drag docks it to a different edge.
    private func updateRootView() {
        hostingView?.rootView = RailView(store: store, edge: placement.edge)
    }

    private func resize(_ panel: RailPanel, providerCount: Int) {
        guard let screen = screenForPlacement() else { return }
        let size = RailView.panelSize(providerCount: providerCount, edge: placement.edge)
        let frame = RailPlacement.frame(for: placement, panelSize: size, in: screen.visibleFrame)
        panel.setFrame(frame, display: true)
    }

    /// The screen `placement.displayID` names, or the screen the menu bar is on
    /// (`NSScreen.screens.first`) when there's no saved ID or it no longer matches any
    /// connected display.
    private func screenForPlacement() -> NSScreen? {
        if let displayID = placement.displayID,
           let screen = NSScreen.screens.first(where: { self.displayID(for: $0) == displayID }) {
            return screen
        }
        return NSScreen.screens.first
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func handleClick() {
        isDragging = false
        guard let panel, let screen = screenForPlacement() else { return }
        // Decide from the mouseDown snapshot, not a fresh `card.isShown` — see
        // cardWasShownAtMouseDown's comment for why a fresh check is wrong here.
        if cardWasShownAtMouseDown {
            card.close()
        } else {
            card.show(anchoredTo: panel.frame, edge: placement.edge, on: screen)
        }

        // Catches up on any visibility/resize change that `applyVisibility` skipped while
        // `isDragging` was true for the mouseDown->mouseUp of this click (onDragBegan sets
        // it on every mouseDown, plain clicks included). Symmetric with the same call at
        // the end of `handleDragEnded` — both are required, neither makes the other
        // redundant, since a click and a drag are mutually exclusive outcomes of the same
        // gesture.
        applyVisibility()
    }

    private func handleDragEnded() {
        isDragging = false
        guard let panel else { return }

        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? panel.screen ?? NSScreen.screens.first else {
            return
        }

        var newPlacement = RailPlacement.snapped(panelFrame: panel.frame, in: screen.visibleFrame)
        newPlacement.displayID = displayID(for: screen)
        placement = newPlacement
        AppSettings.railPlacement = newPlacement
        updateRootView()

        // The edge may have changed (e.g. a side dock dragged to the top), and with it the
        // panel's proportions — a vertical column and a horizontal row of the same
        // provider count are different sizes — so recompute for the new edge rather than
        // reusing the old frame's size.
        let providerCount = RailView.visibleProviders(store: store).count
        let newSize = RailView.panelSize(providerCount: providerCount, edge: newPlacement.edge)
        let targetFrame = RailPlacement.frame(for: newPlacement, panelSize: newSize, in: screen.visibleFrame)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            // Catches up on any visibility/resize change that `applyVisibility` skipped
            // while `isDragging` was true (e.g. a provider appearing or disappearing
            // mid-drag). Deferred to the animation's completion, not run right after
            // `runAnimationGroup` returns, because `applyVisibility` can call `resize(_:)`,
            // which does a synchronous (non-animator) `setFrame` — running that on the next
            // line would cut the snap animation off on the very first frame.
            self?.applyVisibility()
        })
    }

    private func handleScreenParametersChange() {
        // A saved concrete display can disappear (external monitor unplugged) — fall
        // back to the menu bar's screen and persist that, so the rail doesn't keep
        // trying to reposition itself onto a display that no longer exists either.
        if let displayID = placement.displayID, !NSScreen.screens.contains(where: { self.displayID(for: $0) == displayID }) {
            placement.displayID = nil
            AppSettings.railPlacement = placement
        }

        guard let panel else { return }
        resize(panel, providerCount: RailView.visibleProviders(store: store).count)
        // `placement.edge` can't actually change here — only `displayID` above can — but
        // this keeps the root view's edge from ever silently drifting out of sync with it.
        updateRootView()
    }
}
