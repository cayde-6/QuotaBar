import CoreGraphics
import Foundation

/// The screen edge a rail panel is docked to.
enum RailEdge: String, CaseIterable, Sendable {
    case bottom, left, right

    /// Whether the rail itself is laid out horizontally (a row of cells) when docked to
    /// this edge, as opposed to vertically (a column) — this is about the rail's own
    /// orientation, not the axis the edge runs along. `.bottom` is the horizontal edge, so
    /// a rail docked there is stretched out horizontally; `.left`/`.right` are vertical
    /// edges, so a rail docked there stays a vertical column.
    var isHorizontal: Bool {
        switch self {
        case .bottom: return true
        case .left, .right: return false
        }
    }
}

/// Where the rail panel sits: which edge it's docked to, how far along that edge, and
/// on which display. Pure geometry — no AppKit — so it can be unit tested without a
/// running app and without touching real `NSScreen`s.
struct RailPlacement: Equatable, Sendable {
    var edge: RailEdge
    /// 0...1 along the free axis: 0 is the leftmost/topmost position, 1 the rightmost/bottommost.
    var fraction: Double
    /// CGDirectDisplayID of the screen the rail lives on; `nil` means "the screen the
    /// menu bar is on" (`NSScreen.screens.first`), since a saved concrete ID can outlive
    /// the display it named (external monitor unplugged).
    var displayID: UInt32?

    static let `default` = RailPlacement(edge: .right, fraction: 0.2, displayID: nil)

    /// Where the panel should be placed for this placement, in AppKit screen coordinates
    /// (origin bottom-left, y up). The panel is flush against its docked edge; `fraction`
    /// (clamped to 0...1) only moves it along the other, free axis. When the panel is
    /// bigger than the available space on that free axis, travel clamps to zero and the
    /// panel sits flush against the start of that axis too — it is not further clamped to
    /// stay fully inside `visibleFrame` on the docked axis, so a panel taller/wider than
    /// the screen still extends past it there.
    static func frame(for placement: RailPlacement, panelSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let fraction = placement.fraction.clamped(to: 0...1)

        switch placement.edge {
        case .bottom:
            let travel = max(0, visibleFrame.width - panelSize.width)
            let x = visibleFrame.minX + fraction * travel
            let y = visibleFrame.minY
            return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
        case .left:
            let travel = max(0, visibleFrame.height - panelSize.height)
            let x = visibleFrame.minX
            let y = visibleFrame.maxY - panelSize.height - fraction * travel
            return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
        case .right:
            let travel = max(0, visibleFrame.height - panelSize.height)
            let x = visibleFrame.maxX - panelSize.width
            let y = visibleFrame.maxY - panelSize.height - fraction * travel
            return CGRect(origin: CGPoint(x: x, y: y), size: panelSize)
        }
    }

    /// The placement (edge + fraction) implied by a panel frame the user just dragged to
    /// rest at `panelFrame`, picking whichever of the three edges it ended up closest to.
    /// Ties are broken in a fixed order — `bottom`, `left`, `right` — so the choice is
    /// deterministic when a rectangle is equidistant from two edges (see the round-trip
    /// tests for where this matters). `displayID` is left `nil` — this function has no
    /// notion of screens, so the caller (the one place that does) fills it in.
    static func snapped(panelFrame: CGRect, in visibleFrame: CGRect) -> RailPlacement {
        let distanceToBottom = panelFrame.minY - visibleFrame.minY
        let distanceToLeft = panelFrame.minX - visibleFrame.minX
        let distanceToRight = visibleFrame.maxX - panelFrame.maxX

        // Compare magnitudes, not raw values: a panel dragged slightly past an edge
        // gives that edge a negative distance, which must still count as "near" it
        // rather than losing to an edge it's merely far in front of.
        let distances: [(RailEdge, CGFloat)] = [
            (.bottom, abs(distanceToBottom)),
            (.left, abs(distanceToLeft)),
            (.right, abs(distanceToRight)),
        ]
        let edge = distances.min(by: { $0.1 < $1.1 })!.0

        let fraction: Double
        switch edge {
        case .bottom:
            let travel = max(0, visibleFrame.width - panelFrame.width)
            fraction = travel > 0 ? ((panelFrame.minX - visibleFrame.minX) / travel).clamped(to: 0...1) : 0
        case .left, .right:
            let travel = max(0, visibleFrame.height - panelFrame.height)
            fraction = travel > 0 ? ((visibleFrame.maxY - panelFrame.maxY) / travel).clamped(to: 0...1) : 0
        }

        return RailPlacement(edge: edge, fraction: fraction, displayID: nil)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
