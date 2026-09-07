import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: QuotaStore?
    private var popoverController: MenuPopoverController?
    private var statusBarController: StatusBarController?
    private var railPanelController: RailPanelController?
    private var limitsCardController: LimitsCardController?
    private var settingsWindowController: SettingsWindowController?

    /// Last-applied visibility of each surface, as computed in `applySurfaceMode()`. `nil`
    /// until the first call, so that call never closes anything just for lack of a prior
    /// value to compare against.
    private var wasStatusItemVisible: Bool?
    private var wasRailVisible: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = QuotaStore()
        self.store = store

        let settingsWindowController = SettingsWindowController(store: store)
        self.settingsWindowController = settingsWindowController

        let popoverController = MenuPopoverController(store: store) { [weak self] in
            self?.settingsWindowController?.show()
        }
        self.popoverController = popoverController
        self.statusBarController = StatusBarController(store: store, popover: popoverController)

        let limitsCardController = LimitsCardController(store: store) { [weak self] in
            self?.settingsWindowController?.show()
        }
        self.limitsCardController = limitsCardController
        self.railPanelController = RailPanelController(store: store, card: limitsCardController)

        store.onSurfaceModeChange = { [weak self] _ in
            // Both the popover and the card anchor to whichever surface is being switched
            // away from — the status item's button, or the rail panel. That surface can go
            // away as part of applying the new mode (the status item hides in Rail mode;
            // the rail panel orders out in Menu bar mode) while `isShown` stays true, since
            // neither one is watching either surface. Left alone, the next click on
            // whichever surface comes back would see a "shown" popover/card anchored to
            // nothing and just close it instead of opening. Closing both here, before the
            // mode is applied, avoids that regardless of which surface is disappearing.
            self?.popoverController?.close()
            self?.limitsCardController?.close()
            self?.applySurfaceMode()
        }
        applySurfaceMode()
        observeProviderVisibility()

        // Kicks off the first fetch plus the recurring 5-minute auto-refresh loop.
        store.start()
    }

    /// Applies `store.surfaceMode` to both surfaces — see `SurfaceMode.showsMenuBar(railHasContent:)`
    /// for the menu-bar-always-visible fallback this relies on.
    private func applySurfaceMode() {
        guard let store, let statusBarController, let railPanelController else { return }
        let mode = store.surfaceMode
        let railHasContent = !RailView.visibleProviders(store: store).isEmpty
        let statusItemVisible = mode.showsMenuBar(railHasContent: railHasContent)
        let railVisible = mode.showsRail && railHasContent

        // Closes the popover/card exactly when the surface each is anchored to is about to
        // disappear out from under it — not unconditionally on every call, since this runs
        // up to 4 times per auto-refresh cycle (see observeProviderVisibility) and closing
        // every time would slam the popover/card shut under the user on each refresh.
        if wasStatusItemVisible == true, statusItemVisible == false {
            popoverController?.close()
        }
        if wasRailVisible == true, railVisible == false {
            limitsCardController?.close()
        }

        statusBarController.setStatusItemVisible(statusItemVisible)
        railPanelController.setVisible(mode.showsRail)

        wasStatusItemVisible = statusItemVisible
        wasRailVisible = railVisible
    }

    /// Re-applies the surface mode whenever the set of set-up providers could have
    /// changed, since that's what the menu-bar-always-visible fallback above depends on.
    /// Re-registers itself after every fire — `withObservationTracking` only observes up
    /// to its next mutation, not indefinitely. This is also what drives RailPanelController
    /// to resize/show/hide the rail (via `applySurfaceMode` -> `setVisible`) — it has no
    /// observation of its own.
    private func observeProviderVisibility() {
        guard let store else { return }
        withObservationTracking {
            _ = store.codex
            _ = store.claude
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySurfaceMode()
                self?.observeProviderVisibility()
            }
        }
    }
}
