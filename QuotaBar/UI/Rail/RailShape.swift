import SwiftUI

/// The rail panel's dark backing: a contour that widens out to meet the docked screen edge
/// through two concave fillets — the same "notch" construction as the MacBook camera housing
/// or Dynamic Island — rather than meeting it as a flat seam. The free end (away from the
/// docked edge) is a plain rounded corner. Drawn as a single `Path`, not a composite of shapes,
/// so the fill and the stroke can never disagree and show a seam where a fillet meets a
/// straight edge.
struct RailShape: Shape {
    /// The screen edge the rail is docked to.
    let edge: RailEdge
    /// Rounding of the free end, the side facing away from the docked edge.
    var cornerRadius: CGFloat = 16
    /// Radius of the concave fillets where the backing flares out into the docked edge.
    var filletRadius: CGFloat = 12
    /// Rounding of the two corners on the docked side itself. Zero while docked, where that
    /// side is a flat run against the screen edge that the fillets flare out of; grown to a
    /// full round while floating, so a detached rail reads as a finished capsule rather than
    /// a shape with one blunt end.
    var dockedCornerRadius: CGFloat = 0

    /// Lets SwiftUI interpolate all three radii frame-by-frame when they change — the
    /// docked/floating transition driven by `RailPresentation` moves all three at once —
    /// instead of cutting between the two shapes.
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(cornerRadius, AnimatablePair(filletRadius, dockedCornerRadius)) }
        set {
            cornerRadius = newValue.first
            filletRadius = newValue.second.first
            dockedCornerRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch edge {
        case .right: return pathDockedRight(in: rect)
        case .left: return pathDockedLeft(in: rect)
        case .bottom: return pathDockedBottom(in: rect)
        }
    }

    // Each fillet hangs off an *anchor* set back from the docked corner by
    // `dockedCornerRadius`, rather than off the corner itself. That is what lets both radii
    // be non-zero at once, as they are on every frame of the docked/floating transition:
    // the rounded corner eats its way in from the corner, the fillet flares from where the
    // rounding leaves off, and neither has to know the other's value. Both degenerate
    // cleanly — at `dockedCornerRadius == 0` the anchor is the corner and the contour is
    // exactly the docked shape; at `filletRadius == 0` the fillet arc collapses onto the
    // anchor point and the contour is a plain rounded rectangle.

    /// Docked to the right edge of the screen: the rail's own right side sits flush against
    /// it. Traced clockwise from the docked edge's top end, over the top fillet, around the
    /// free (left) side's rounded corners, back over the bottom fillet, and up the docked edge.
    private func pathDockedRight(in rect: CGRect) -> Path {
        let r = cornerRadius
        let fr = filletRadius
        let dr = dockedCornerRadius
        let dockedX = rect.maxX
        let anchorX = dockedX - dr
        let freeX = rect.minX
        let top = rect.minY
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: dockedX, y: top + dr))
        path.addArc(tangent1End: CGPoint(x: dockedX, y: top), tangent2End: CGPoint(x: anchorX, y: top), radius: dr)
        path.addArc(
            center: CGPoint(x: anchorX - fr, y: top), radius: fr,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: freeX + r, y: top + fr))
        path.addArc(tangent1End: CGPoint(x: freeX, y: top + fr), tangent2End: CGPoint(x: freeX, y: top + fr + r), radius: r)
        path.addLine(to: CGPoint(x: freeX, y: bottom - fr - r))
        path.addArc(tangent1End: CGPoint(x: freeX, y: bottom - fr), tangent2End: CGPoint(x: freeX + r, y: bottom - fr), radius: r)
        path.addLine(to: CGPoint(x: anchorX - fr, y: bottom - fr))
        path.addArc(
            center: CGPoint(x: anchorX - fr, y: bottom), radius: fr,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.addArc(tangent1End: CGPoint(x: dockedX, y: bottom), tangent2End: CGPoint(x: dockedX, y: bottom - dr), radius: dr)
        path.closeSubpath()
        return path
    }

    /// Mirror of `pathDockedRight`: docked to the left edge, so the fillets flare into the
    /// left edge and the free side's rounded corners sit on the right.
    private func pathDockedLeft(in rect: CGRect) -> Path {
        let r = cornerRadius
        let fr = filletRadius
        let dr = dockedCornerRadius
        let dockedX = rect.minX
        let anchorX = dockedX + dr
        let freeX = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: dockedX, y: top + dr))
        path.addArc(tangent1End: CGPoint(x: dockedX, y: top), tangent2End: CGPoint(x: anchorX, y: top), radius: dr)
        path.addArc(
            center: CGPoint(x: anchorX + fr, y: top), radius: fr,
            startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
        )
        path.addLine(to: CGPoint(x: freeX - r, y: top + fr))
        path.addArc(tangent1End: CGPoint(x: freeX, y: top + fr), tangent2End: CGPoint(x: freeX, y: top + fr + r), radius: r)
        path.addLine(to: CGPoint(x: freeX, y: bottom - fr - r))
        path.addArc(tangent1End: CGPoint(x: freeX, y: bottom - fr), tangent2End: CGPoint(x: freeX - r, y: bottom - fr), radius: r)
        path.addLine(to: CGPoint(x: anchorX + fr, y: bottom - fr))
        path.addArc(
            center: CGPoint(x: anchorX + fr, y: bottom), radius: fr,
            startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true
        )
        path.addArc(tangent1End: CGPoint(x: dockedX, y: bottom), tangent2End: CGPoint(x: dockedX, y: bottom - dr), radius: dr)
        path.closeSubpath()
        return path
    }

    /// Docked to the bottom edge of the screen — the rail is a horizontal row rather than a
    /// vertical column, so the fillets sit at the panel's left and right ends and flare down
    /// into the docked bottom edge; the free side's rounded corners are on top.
    private func pathDockedBottom(in rect: CGRect) -> Path {
        let r = cornerRadius
        let fr = filletRadius
        let dr = dockedCornerRadius
        let left = rect.minX
        let right = rect.maxX
        let dockedY = rect.maxY
        let anchorY = dockedY - dr
        let freeY = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: left + dr, y: dockedY))
        path.addArc(tangent1End: CGPoint(x: left, y: dockedY), tangent2End: CGPoint(x: left, y: anchorY), radius: dr)
        path.addArc(
            center: CGPoint(x: left, y: anchorY - fr), radius: fr,
            startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true
        )
        path.addLine(to: CGPoint(x: left + fr, y: freeY + r))
        path.addArc(tangent1End: CGPoint(x: left + fr, y: freeY), tangent2End: CGPoint(x: left + fr + r, y: freeY), radius: r)
        path.addLine(to: CGPoint(x: right - fr - r, y: freeY))
        path.addArc(tangent1End: CGPoint(x: right - fr, y: freeY), tangent2End: CGPoint(x: right - fr, y: freeY + r), radius: r)
        path.addLine(to: CGPoint(x: right - fr, y: anchorY - fr))
        path.addArc(
            center: CGPoint(x: right, y: anchorY - fr), radius: fr,
            startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
        )
        path.addArc(tangent1End: CGPoint(x: right, y: dockedY), tangent2End: CGPoint(x: right - dr, y: dockedY), radius: dr)
        path.closeSubpath()
        return path
    }
}
