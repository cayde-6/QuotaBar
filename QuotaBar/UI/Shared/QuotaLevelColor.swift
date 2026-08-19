import SwiftUI

/// Popover color for a quota level. Distinct from `StatusBarPalette`, which colors the
/// rendered menu bar image with hand-picked RGB values — the popover instead uses plain
/// system colors, since it renders inside a normal window/appearance context where those
/// are reliable.
extension QuotaLevel {
    /// `.yellow` reads poorly as text color in both themes, so warning uses `.orange`
    /// instead — same "not healthy, not critical" meaning, actually legible.
    var menuColor: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
