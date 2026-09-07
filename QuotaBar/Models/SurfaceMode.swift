import Foundation

/// Which output surface(s) show the quota readout: the classic menu bar item, the
/// floating rail panel, or both at once.
enum SurfaceMode: String, CaseIterable, Sendable {
    case menuBar, rail, both

    /// Whether this mode calls for the menu bar item on its own terms, ignoring whether
    /// the rail has anything to draw. Use `showsMenuBar(railHasContent:)` for the actual
    /// visibility decision — it also covers the case this alone doesn't.
    var prefersMenuBar: Bool {
        self == .menuBar || self == .both
    }

    var showsRail: Bool {
        self == .rail || self == .both
    }

    /// The menu bar item stays visible regardless of mode whenever the rail has nothing
    /// to draw — otherwise Rail mode with no set-up providers would leave the user no way
    /// to open the popover at all.
    func showsMenuBar(railHasContent: Bool) -> Bool {
        prefersMenuBar || !railHasContent
    }

    var title: String {
        switch self {
        case .menuBar: return "Menu bar"
        case .rail: return "Widget"
        case .both: return "Both"
        }
    }
}
