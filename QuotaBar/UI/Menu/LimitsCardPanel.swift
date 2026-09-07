import AppKit

/// The floating, borderless panel the dark limits card lives in when opened from the rail
/// widget: always on top, visible on every Space, with no system arrow to paint (see
/// LimitsCardController for why the rail widget can't use NSPopover for this).
final class LimitsCardPanel: NSPanel {
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
        // Not for the window's own frame — it's borderless, so there's no titlebar or
        // border to theme. This forces the SwiftUI content inside into the dark color
        // scheme, so system .primary/.secondary text renders light-on-dark instead of
        // the default light-scheme dark-on-dark. NSPopover gets the same effect via
        // popover.appearance = NSAppearance(named: .darkAqua).
        appearance = NSAppearance(named: .darkAqua)
    }

    // Borderless panels can't become key by default, which would leave the Refresh button
    // and gear inside the card unable to respond like ordinary controls.
    override var canBecomeKey: Bool { true }
}
