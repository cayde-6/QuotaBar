import AppKit

/// Transparent overlay sitting on top of the rail's SwiftUI content, handling click and
/// drag. `isMovableByWindowBackground` isn't an option here — it consumes mouseDown
/// itself, which makes a plain click on the rail unreliable.
final class RailInteractionView: NSView {
    var onClick: (() -> Void)?
    var onMouseDown: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    /// Origin of the window at the start of the current gesture, captured in `mouseDown`
    /// and consumed in `mouseUp`. `nil` whenever no gesture is in flight.
    private var gestureStartOrigin: NSPoint?

    /// Below this many points of origin movement on either axis, a gesture counts as a click
    /// rather than a drag — guards against window-server jitter reclassifying an ordinary
    /// click as a drag, not meant to catch intentional dragging.
    private let clickOriginJitterThreshold: CGFloat = 3

    /// Hands the whole gesture to AppKit instead of tracking `mouseDragged`/`mouseUp` by
    /// hand. A hand-rolled drag has to compare the cursor position at `mouseDown` against
    /// the position on the first `mouseDragged` to tell a click from a drag — and those two
    /// events aren't guaranteed to arrive in the order they were generated (synthetic input,
    /// remote access, some trackpad/tablet drivers), so that comparison can see a huge,
    /// spurious delta and turn an ordinary click into a drag. `performDrag(with:)` moves the
    /// window itself and isn't exposed to that ordering problem at all.
    override func mouseDown(with event: NSEvent) {
        // Reports mouseDown, not just onClick, so RailPanelController can snapshot the
        // card's shown state before it closes itself on this same mouseDown — see the
        // comment at RailPanelController's cardWasShownAtMouseDown. The widget opens
        // LimitsCardController's own panel here, not an NSPopover. Must run before
        // performDrag.
        onMouseDown?()

        gestureStartOrigin = window?.frame.origin
        onDragBegan?()

        // Returns immediately — it hands the gesture to the window server and does not wait
        // for the mouse button to come back up. The window then keeps moving asynchronously,
        // and this view keeps receiving mouseDragged for the rest of the gesture, so a click
        // can't be told apart from a drag here; that has to wait until mouseUp, once the
        // window's final origin is known.
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        // Also filters out the duplicate mouseUp the window server sends after a
        // performDrag-driven move: the first mouseUp clears gestureStartOrigin, so the
        // second one falls through here and is ignored. Without this guard onDragEnded would
        // fire twice and save the panel's position twice.
        guard let start = gestureStartOrigin else { return }
        gestureStartOrigin = nil

        // A drag of negligible length is indistinguishable from a click, so the window's
        // origin moving (beyond a small jitter threshold) is what tells the two apart. If
        // `window` is nil, that's treated as a drag, not a click, same as the old exact
        // comparison did.
        if let origin = window?.frame.origin,
           abs(origin.x - start.x) < clickOriginJitterThreshold,
           abs(origin.y - start.y) < clickOriginJitterThreshold {
            onClick?()
        } else {
            onDragEnded?()
        }
    }

    // Without this, the rail's first click while some other app is active just activates
    // QuotaBar instead of registering as a click on the panel.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
