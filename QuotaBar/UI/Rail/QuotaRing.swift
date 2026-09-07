import SwiftUI

/// Single progress ring for one provider's short (5-hour) window, with the provider's
/// mark centered inside. The weekly window is shown only in the popover now.
struct QuotaRing: View {
    let window: QuotaWindow?
    let provider: QuotaProvider

    private static let lineWidth: CGFloat = 3
    private static let diameter: CGFloat = 34
    private static let hubDiameter: CGFloat = 28

    var body: some View {
        ZStack {
            // The track is white-with-opacity rather than the system `.secondary` because
            // the rail's backing is always dark, independent of the system's light/dark mode.
            Circle()
                .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .butt))

            // Dark hub behind the mark so it reads as sitting on a disc rather than
            // hanging in the ring's empty center.
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: Self.hubDiameter, height: Self.hubDiameter)

            if let window {
                Circle()
                    .trim(from: 0, to: window.remainingPercentage / 100)
                    .stroke(provider.accentColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .butt))
                    // Starts the arc at 12 o'clock instead of trim's default 3 o'clock,
                    // and trim already draws clockwise, so this alone gets both.
                    .rotationEffect(.degrees(-90))
            }

            Image(provider.iconName)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }
}
