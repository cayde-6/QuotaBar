import CoreGraphics
import Foundation
import Testing

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
private let panel = CGSize(width: 44, height: 112)

@Suite("RailPlacement.frame")
struct RailPlacementFrameTests {
    @Test("bottom edge sits flush against the bottom, sliding across x with fraction")
    func bottomEdge() {
        let atStart = RailPlacement.frame(for: RailPlacement(edge: .bottom, fraction: 0, displayID: nil), panelSize: panel, in: screen)
        #expect(atStart == CGRect(x: 0, y: 0, width: panel.width, height: panel.height))

        let atMiddle = RailPlacement.frame(for: RailPlacement(edge: .bottom, fraction: 0.5, displayID: nil), panelSize: panel, in: screen)
        #expect(atMiddle.origin.y == 0)
        #expect(atMiddle.origin.x == 0.5 * (screen.width - panel.width))

        let atEnd = RailPlacement.frame(for: RailPlacement(edge: .bottom, fraction: 1, displayID: nil), panelSize: panel, in: screen)
        #expect(atEnd.origin.x == screen.width - panel.width)
        #expect(atEnd.origin.y == 0)
    }

    @Test("left edge sits flush against the left, sliding across y with fraction")
    func leftEdge() {
        let atStart = RailPlacement.frame(for: RailPlacement(edge: .left, fraction: 0, displayID: nil), panelSize: panel, in: screen)
        #expect(atStart == CGRect(x: 0, y: screen.height - panel.height, width: panel.width, height: panel.height))

        let atMiddle = RailPlacement.frame(for: RailPlacement(edge: .left, fraction: 0.5, displayID: nil), panelSize: panel, in: screen)
        #expect(atMiddle.origin.x == 0)
        #expect(atMiddle.origin.y == screen.height - panel.height - 0.5 * (screen.height - panel.height))

        let atEnd = RailPlacement.frame(for: RailPlacement(edge: .left, fraction: 1, displayID: nil), panelSize: panel, in: screen)
        #expect(atEnd.origin.x == 0)
        #expect(atEnd.origin.y == 0)
    }

    @Test("right edge sits flush against the right, sliding across y with fraction")
    func rightEdge() {
        let atStart = RailPlacement.frame(for: RailPlacement(edge: .right, fraction: 0, displayID: nil), panelSize: panel, in: screen)
        #expect(atStart.origin.x == screen.width - panel.width)
        #expect(atStart.origin.y == screen.height - panel.height)

        let atEnd = RailPlacement.frame(for: RailPlacement(edge: .right, fraction: 1, displayID: nil), panelSize: panel, in: screen)
        #expect(atEnd.origin.x == screen.width - panel.width)
        #expect(atEnd.origin.y == 0)
    }

    @Test("fraction below 0 or above 1 is clamped before use")
    func fractionClamped() {
        let below = RailPlacement.frame(for: RailPlacement(edge: .bottom, fraction: -1, displayID: nil), panelSize: panel, in: screen)
        let atZero = RailPlacement.frame(for: RailPlacement(edge: .bottom, fraction: 0, displayID: nil), panelSize: panel, in: screen)
        #expect(below == atZero)

        let above = RailPlacement.frame(for: RailPlacement(edge: .right, fraction: 5, displayID: nil), panelSize: panel, in: screen)
        let atOne = RailPlacement.frame(for: RailPlacement(edge: .right, fraction: 1, displayID: nil), panelSize: panel, in: screen)
        #expect(above == atOne)
    }

    // fraction has no effect here regardless of value, since travel along the free axis
    // clamps to zero once the panel no longer fits — origin on the docked axis still
    // tracks the oversized panel size and so can land outside visibleFrame there, which
    // is expected: see the comment on frame(for:) above.
    @Test("a panel wider or taller than the available space clamps travel on the free axis to zero")
    func oversizedPanel() {
        let hugePanel = CGSize(width: screen.width + 200, height: screen.height + 200)

        for fraction in [0.0, 0.5, 1.0] {
            let bottom = RailPlacement.frame(for: RailPlacement(edge: .bottom, fraction: fraction, displayID: nil), panelSize: hugePanel, in: screen)
            #expect(bottom.origin.x == screen.minX)
            #expect(bottom.origin.y == screen.minY)

            let left = RailPlacement.frame(for: RailPlacement(edge: .left, fraction: fraction, displayID: nil), panelSize: hugePanel, in: screen)
            #expect(left.origin.x == screen.minX)
            #expect(left.origin.y == screen.maxY - hugePanel.height)

            let right = RailPlacement.frame(for: RailPlacement(edge: .right, fraction: fraction, displayID: nil), panelSize: hugePanel, in: screen)
            #expect(right.origin.x == screen.maxX - hugePanel.width)
            #expect(right.origin.y == screen.maxY - hugePanel.height)
        }
    }

    @Test("visibleFrame with a non-zero origin is handled relatively, not absolutely")
    func offsetVisibleFrame() {
        let external = CGRect(x: -1512, y: -200, width: 1512, height: 982)

        let atZero = RailPlacement.frame(for: RailPlacement(edge: .bottom, fraction: 0, displayID: nil), panelSize: panel, in: external)
        #expect(atZero.origin.x == external.minX)
        #expect(atZero.origin.y == external.minY)

        let atMiddle = RailPlacement.frame(for: RailPlacement(edge: .left, fraction: 0.5, displayID: nil), panelSize: panel, in: external)
        #expect(atMiddle.origin.x == external.minX)
        #expect(atMiddle.origin.y == external.maxY - panel.height - 0.5 * (external.height - panel.height))
    }
}

@Suite("RailPlacement.snapped")
struct RailPlacementSnappedTests {
    @Test("a panel flush against the bottom snaps to bottom")
    func snapsBottom() {
        let frame = CGRect(x: 400, y: screen.minY, width: panel.width, height: panel.height)
        let placement = RailPlacement.snapped(panelFrame: frame, in: screen)
        #expect(placement.edge == .bottom)
        #expect(placement.displayID == nil)
    }

    @Test("a panel flush against the left snaps to left")
    func snapsLeft() {
        let frame = CGRect(x: 0, y: 300, width: panel.width, height: panel.height)
        let placement = RailPlacement.snapped(panelFrame: frame, in: screen)
        #expect(placement.edge == .left)
        #expect(placement.displayID == nil)
    }

    @Test("a panel flush against the right snaps to right")
    func snapsRight() {
        let frame = CGRect(x: screen.maxX - panel.width, y: 300, width: panel.width, height: panel.height)
        let placement = RailPlacement.snapped(panelFrame: frame, in: screen)
        #expect(placement.edge == .right)
        #expect(placement.displayID == nil)
    }

    @Test("zero travel space yields a fraction of 0")
    func zeroTravelYieldsZeroFraction() {
        let hugePanel = CGSize(width: screen.width + 200, height: panel.height)
        let frame = CGRect(x: screen.minX - 50, y: screen.minY, width: hugePanel.width, height: hugePanel.height)
        let placement = RailPlacement.snapped(panelFrame: frame, in: screen)
        #expect(placement.edge == .bottom)
        #expect(placement.fraction == 0)
    }
}

@Suite("RailPlacement round-trip")
struct RailPlacementRoundTripTests {
    /// With only three edges left, a corner is describable by two adjacent edges at the
    /// fraction that puts the panel flush with both — `frame(for:)` produces an identical
    /// rectangle either way, so `snapped` (which only sees the rectangle) cannot tell
    /// those two inputs apart, and resolves the tie by the fixed order documented on
    /// `snapped` itself: `bottom`, `left`, `right`.
    ///
    /// The top corners are no longer ties: with no `.top` edge to compete, `.left`@0 and
    /// `.right`@0 are each the sole candidate for their corner, so `snapped` recovers them
    /// uniquely.
    ///
    /// - Bottom-left corner: `.bottom`@0 and `.left`@1 both land there; `.bottom` wins.
    /// - Bottom-right corner: `.bottom`@1 and `.right`@1 both land there; `.bottom` wins.
    private func expectedRoundTrip(for edge: RailEdge, fraction: Double) -> (edge: RailEdge, fraction: Double) {
        switch (edge, fraction) {
        case (.left, 1): return (.bottom, 0)
        case (.right, 1): return (.bottom, 1)
        default: return (edge, fraction)
        }
    }

    @Test("snapping the frame produced for a placement recovers the same edge and fraction", arguments: RailEdge.allCases, [0.0, 0.25, 1.0])
    func roundTrip(edge: RailEdge, fraction: Double) {
        let original = RailPlacement(edge: edge, fraction: fraction, displayID: nil)
        let frame = RailPlacement.frame(for: original, panelSize: panel, in: screen)
        let recovered = RailPlacement.snapped(panelFrame: frame, in: screen)
        let expected = expectedRoundTrip(for: edge, fraction: fraction)

        #expect(recovered.edge == expected.edge)
        #expect(abs(recovered.fraction - expected.fraction) < 0.001)
    }
}
