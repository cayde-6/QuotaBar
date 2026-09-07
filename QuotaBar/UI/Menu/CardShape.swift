import SwiftUI

/// The limits card's outline: a rounded rectangle with a pointer sticking out of
/// whichever side faces the rail widget it was opened from, shaped to match the system
/// `NSPopover` arrow — a concave shoulder blending into the body, straightening into a
/// slightly rounded tip, rather than a plain triangle. Drawn as a single `Path` (rather
/// than a rounded rectangle with a pointer overlaid on top) so the same contour can be
/// used for the fill, the clip, and the stroke alike — a composite of two shapes would
/// leave a visible seam where the pointer meets the rectangle on the stroke.
struct CardShape: Shape {
    /// Which side of the card the pointer sticks out of — the side facing the rail.
    let pointerEdge: RailEdge
    var cornerRadius: CGFloat = 16
    var pointerBase: CGFloat = 18
    var pointerDepth: CGFloat = 9
    /// Offset of the pointer's tip along the side it sits on, in points, from that side's
    /// center. Positive moves it in the direction of growing coordinates — down for
    /// `.left`/`.right`, right for `.bottom` — so the caller can slide the pointer back
    /// toward a rail widget after the card's own frame got clamped to the screen and no
    /// longer sits centered on it.
    var pointerOffset: CGFloat = 0

    /// Radius of the small arc joining the pointer's two flanks at its tip, so it reads
    /// as slightly rounded rather than needle-sharp.
    private static let pointerTipRadius: CGFloat = 1.5
    /// Each flank is a cubic Bezier. Its first control point sits exactly on the body
    /// edge — same x as the shoulder for `.right`/`.left`, same y for `.bottom` — and is
    /// offset only *along* that edge, toward the tip, by this fraction of `pointerBase`.
    /// Keeping the control point on the edge line makes the curve's tangent at the
    /// shoulder match the edge's own direction, so the flank continues the body's edge
    /// instead of breaking away at a corner.
    private static let pointerShoulderControlAlongFraction: CGFloat = 0.30
    /// The flank's second control point sits back from the tip along the pointer's
    /// depth axis by this fraction of `pointerDepth`, shaping the final approach to the
    /// tip rather than the departure from the shoulder.
    private static let pointerTipControlDepthFraction: CGFloat = 0.35
    /// The flank's second control point sits this close to the pointer's centerline, as
    /// a fraction of `pointerBase` — pulled in from the shoulder's width toward the
    /// narrow tip.
    private static let pointerTipControlSpreadFraction: CGFloat = 0.10

    /// Clamps `pointerOffset` so the pointer stays within the straight run of the side it
    /// sits on — never sliding onto the rounded corner at either end. `sideLength` is that
    /// side's own extent (the body's height for `.left`/`.right`, its width for `.bottom`).
    /// A side too short to leave any room at all (a degenerate/tiny card) falls back to no
    /// offset rather than a negative range.
    private func clampedPointerOffset(sideLength: CGFloat) -> CGFloat {
        let maxOffset = sideLength / 2 - cornerRadius - pointerBase / 2
        guard maxOffset > 0 else { return 0 }
        return min(max(pointerOffset, -maxOffset), maxOffset)
    }

    func path(in rect: CGRect) -> Path {
        switch pointerEdge {
        case .right: return pathPointingRight(in: rect)
        case .left: return pathPointingLeft(in: rect)
        case .bottom: return pathPointingDown(in: rect)
        }
    }

    /// Rail docked to the right of the card, so the pointer sticks out of the card's
    /// right edge. The card's body is `rect` inset on that side by `pointerDepth`; the
    /// pointer's flanks curve from the body's right edge to a tip touching `rect.maxX`.
    /// Traced clockwise starting at the top-left corner.
    private func pathPointingRight(in rect: CGRect) -> Path {
        let r = cornerRadius
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width - pointerDepth, height: rect.height)
        let midY = body.midY + clampedPointerOffset(sideLength: body.height)

        let tipRadius = Self.pointerTipRadius
        let controlAlong = pointerBase * Self.pointerShoulderControlAlongFraction
        let controlDepth = pointerDepth * Self.pointerTipControlDepthFraction
        let controlSpread = pointerBase * Self.pointerTipControlSpreadFraction
        let shoulderTop = CGPoint(x: body.maxX, y: midY - pointerBase / 2)
        let shoulderBottom = CGPoint(x: body.maxX, y: midY + pointerBase / 2)
        let tipTop = CGPoint(x: rect.maxX - tipRadius, y: midY - tipRadius)
        let tipBottom = CGPoint(x: rect.maxX - tipRadius, y: midY + tipRadius)
        // On the body edge, offset along it toward the tip — matches the edge's tangent.
        let controlShoulderTop = CGPoint(x: body.maxX, y: shoulderTop.y + controlAlong)
        let controlShoulderBottom = CGPoint(x: body.maxX, y: shoulderBottom.y - controlAlong)
        // Pulled toward the tip and the centerline, shaping the final approach.
        let controlTipTop = CGPoint(x: rect.maxX - controlDepth, y: midY - controlSpread)
        let controlTipBottom = CGPoint(x: rect.maxX - controlDepth, y: midY + controlSpread)
        let tipControl = CGPoint(x: rect.maxX, y: midY)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        path.addLine(to: shoulderTop)
        path.addCurve(to: tipTop, control1: controlShoulderTop, control2: controlTipTop)
        path.addQuadCurve(to: tipBottom, control: tipControl)
        path.addCurve(to: shoulderBottom, control1: controlTipBottom, control2: controlShoulderBottom)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }

    /// Mirror of `pathPointingRight`: rail docked to the left, pointer on the card's left
    /// edge, body inset on that side by `pointerDepth`.
    private func pathPointingLeft(in rect: CGRect) -> Path {
        let r = cornerRadius
        let body = CGRect(x: rect.minX + pointerDepth, y: rect.minY, width: rect.width - pointerDepth, height: rect.height)
        let midY = body.midY + clampedPointerOffset(sideLength: body.height)

        let tipRadius = Self.pointerTipRadius
        let controlAlong = pointerBase * Self.pointerShoulderControlAlongFraction
        let controlDepth = pointerDepth * Self.pointerTipControlDepthFraction
        let controlSpread = pointerBase * Self.pointerTipControlSpreadFraction
        let shoulderBottom = CGPoint(x: body.minX, y: midY + pointerBase / 2)
        let shoulderTop = CGPoint(x: body.minX, y: midY - pointerBase / 2)
        let tipBottom = CGPoint(x: rect.minX + tipRadius, y: midY + tipRadius)
        let tipTop = CGPoint(x: rect.minX + tipRadius, y: midY - tipRadius)
        // On the body edge, offset along it toward the tip — matches the edge's tangent.
        let controlShoulderBottom = CGPoint(x: body.minX, y: shoulderBottom.y - controlAlong)
        let controlShoulderTop = CGPoint(x: body.minX, y: shoulderTop.y + controlAlong)
        // Pulled toward the tip and the centerline, shaping the final approach.
        let controlTipBottom = CGPoint(x: rect.minX + controlDepth, y: midY + controlSpread)
        let controlTipTop = CGPoint(x: rect.minX + controlDepth, y: midY - controlSpread)
        let tipControl = CGPoint(x: rect.minX, y: midY)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        path.addLine(to: shoulderBottom)
        path.addCurve(to: tipBottom, control1: controlShoulderBottom, control2: controlTipBottom)
        path.addQuadCurve(to: tipTop, control: tipControl)
        path.addCurve(to: shoulderTop, control1: controlTipTop, control2: controlShoulderTop)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }

    /// Rail docked below the card, pointer on the card's bottom edge, body inset on that
    /// side by `pointerDepth`.
    private func pathPointingDown(in rect: CGRect) -> Path {
        let r = cornerRadius
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - pointerDepth)
        let midX = body.midX + clampedPointerOffset(sideLength: body.width)

        let tipRadius = Self.pointerTipRadius
        let controlAlong = pointerBase * Self.pointerShoulderControlAlongFraction
        let controlDepth = pointerDepth * Self.pointerTipControlDepthFraction
        let controlSpread = pointerBase * Self.pointerTipControlSpreadFraction
        let shoulderRight = CGPoint(x: midX + pointerBase / 2, y: body.maxY)
        let shoulderLeft = CGPoint(x: midX - pointerBase / 2, y: body.maxY)
        let tipRight = CGPoint(x: midX + tipRadius, y: rect.maxY - tipRadius)
        let tipLeft = CGPoint(x: midX - tipRadius, y: rect.maxY - tipRadius)
        // On the body edge, offset along it toward the tip — matches the edge's tangent.
        let controlShoulderRight = CGPoint(x: shoulderRight.x - controlAlong, y: body.maxY)
        let controlShoulderLeft = CGPoint(x: shoulderLeft.x + controlAlong, y: body.maxY)
        // Pulled toward the tip and the centerline, shaping the final approach.
        let controlTipRight = CGPoint(x: midX + controlSpread, y: rect.maxY - controlDepth)
        let controlTipLeft = CGPoint(x: midX - controlSpread, y: rect.maxY - controlDepth)
        let tipControl = CGPoint(x: midX, y: rect.maxY)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        path.addLine(to: shoulderRight)
        path.addCurve(to: tipRight, control1: controlShoulderRight, control2: controlTipRight)
        path.addQuadCurve(to: tipLeft, control: tipControl)
        path.addCurve(to: shoulderLeft, control1: controlTipLeft, control2: controlShoulderLeft)
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }
}
