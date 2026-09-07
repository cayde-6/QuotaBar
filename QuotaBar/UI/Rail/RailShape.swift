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

    func path(in rect: CGRect) -> Path {
        switch edge {
        case .right: return pathDockedRight(in: rect)
        case .left: return pathDockedLeft(in: rect)
        case .bottom: return pathDockedBottom(in: rect)
        }
    }

    /// Docked to the right edge of the screen: the rail's own right side sits flush against
    /// it. Traced clockwise from the top of the docked edge: a concave fillet flares the
    /// docked edge out to the panel's full height, across the top of the body, around the
    /// free (left) side's rounded corners, back across the bottom of the body, and a second
    /// concave fillet flares out again before the straight run back up the docked edge.
    private func pathDockedRight(in rect: CGRect) -> Path {
        let r = cornerRadius
        let fr = filletRadius
        let dockedX = rect.maxX
        let freeX = rect.minX
        let top = rect.minY
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: dockedX, y: top))
        path.addArc(
            center: CGPoint(x: dockedX - fr, y: top), radius: fr,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: freeX + r, y: top + fr))
        path.addArc(tangent1End: CGPoint(x: freeX, y: top + fr), tangent2End: CGPoint(x: freeX, y: top + fr + r), radius: r)
        path.addLine(to: CGPoint(x: freeX, y: bottom - fr - r))
        path.addArc(tangent1End: CGPoint(x: freeX, y: bottom - fr), tangent2End: CGPoint(x: freeX + r, y: bottom - fr), radius: r)
        path.addLine(to: CGPoint(x: dockedX - fr, y: bottom - fr))
        path.addArc(
            center: CGPoint(x: dockedX - fr, y: bottom), radius: fr,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: dockedX, y: top))
        path.closeSubpath()
        return path
    }

    /// Mirror of `pathDockedRight`: docked to the left edge, so the fillets flare into the
    /// left edge and the free side's rounded corners sit on the right.
    private func pathDockedLeft(in rect: CGRect) -> Path {
        let r = cornerRadius
        let fr = filletRadius
        let dockedX = rect.minX
        let freeX = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: dockedX, y: top))
        path.addArc(
            center: CGPoint(x: dockedX + fr, y: top), radius: fr,
            startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
        )
        path.addLine(to: CGPoint(x: freeX - r, y: top + fr))
        path.addArc(tangent1End: CGPoint(x: freeX, y: top + fr), tangent2End: CGPoint(x: freeX, y: top + fr + r), radius: r)
        path.addLine(to: CGPoint(x: freeX, y: bottom - fr - r))
        path.addArc(tangent1End: CGPoint(x: freeX, y: bottom - fr), tangent2End: CGPoint(x: freeX - r, y: bottom - fr), radius: r)
        path.addLine(to: CGPoint(x: dockedX + fr, y: bottom - fr))
        path.addArc(
            center: CGPoint(x: dockedX + fr, y: bottom), radius: fr,
            startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true
        )
        path.addLine(to: CGPoint(x: dockedX, y: top))
        path.closeSubpath()
        return path
    }

    /// Docked to the bottom edge of the screen — the rail is a horizontal row rather than a
    /// vertical column, so the fillets sit at the panel's left and right ends and flare down
    /// into the docked bottom edge; the free side's rounded corners are on top.
    private func pathDockedBottom(in rect: CGRect) -> Path {
        let r = cornerRadius
        let fr = filletRadius
        let left = rect.minX
        let right = rect.maxX
        let dockedY = rect.maxY
        let freeY = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: left, y: dockedY))
        path.addArc(
            center: CGPoint(x: left, y: dockedY - fr), radius: fr,
            startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true
        )
        path.addLine(to: CGPoint(x: left + fr, y: freeY + r))
        path.addArc(tangent1End: CGPoint(x: left + fr, y: freeY), tangent2End: CGPoint(x: left + fr + r, y: freeY), radius: r)
        path.addLine(to: CGPoint(x: right - fr - r, y: freeY))
        path.addArc(tangent1End: CGPoint(x: right - fr, y: freeY), tangent2End: CGPoint(x: right - fr, y: freeY + r), radius: r)
        path.addLine(to: CGPoint(x: right - fr, y: dockedY - fr))
        path.addArc(
            center: CGPoint(x: right, y: dockedY - fr), radius: fr,
            startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
        )
        path.addLine(to: CGPoint(x: left, y: dockedY))
        path.closeSubpath()
        return path
    }
}
