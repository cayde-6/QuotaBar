import AppKit

/// The floating, borderless panel the rail lives in: always on top, click-through-proof,
/// draggable by hand (see RailInteractionView), and visible on every Space.
final class RailPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    // Borderless panels can't become key by default, which would leave a transient
    // popover opened from this panel with no way to detect an outside click and close.
    override var canBecomeKey: Bool { true }
}
