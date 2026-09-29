import SwiftUI

/// Floating readout: one ring-and-percentage cell per set-up provider, laid out as a
/// column when docked to a side edge or a row when docked to top/bottom. Unlike
/// StatusBarView, this is a live SwiftUI hierarchy — it's hosted directly, never
/// rasterized — so it updates and animates on its own as `store` changes.
struct RailView: View {
    let store: QuotaStore
    let edge: RailEdge
    let presentation: RailPresentation

    static let cellWidth: CGFloat = 70
    static let cellHeight: CGFloat = 72
    static let cornerRadius: CGFloat = 16
    /// Radius of the concave fillets where the backing flares out into the docked edge — see
    /// `RailShape`. Shape only: how far the cells sit from the panel's ends is
    /// `contentEdgeInset`, deliberately a separate number.
    static let filletRadius: CGFloat = 24
    /// How far the cells sit from the panel's ends along the docked axis, and therefore how
    /// much the panel grows there. Deliberately larger than `filletRadius`: at exactly the
    /// fillet radius the outermost ring starts where the fillet's curve does, and the two
    /// crowd each other.
    static let contentEdgeInset: CGFloat = 34

    /// Codex first, then Claude — same order as the menu bar and popover — excluding
    /// providers hidden in Settings or not set up on this machine. The
    /// controller calls this exact method to size and position the panel, so it and the
    /// view can never disagree about which providers are shown.
    static func visibleProviders(store: QuotaStore) -> [QuotaProvider] {
        store.visibleProviders
    }

    /// The panel's size for `edge`: a single-cell-wide column of `providerCount` cells on
    /// a side edge, or a single-cell-tall row of `providerCount` cells on top/bottom — plus
    /// two `contentEdgeInset`-wide margins along the docked axis (width for `.bottom`, height
    /// for a side edge), which hold `RailShape`'s concave fillets and keep the outermost cell
    /// clear of them.
    static func panelSize(providerCount: Int, edge: RailEdge) -> CGSize {
        edge.isHorizontal
            ? CGSize(width: cellWidth * CGFloat(providerCount) + 2 * contentEdgeInset, height: cellHeight)
            : CGSize(width: cellWidth, height: cellHeight * CGFloat(providerCount) + 2 * contentEdgeInset)
    }

    private static func state(for provider: QuotaProvider, in store: QuotaStore) -> ProviderState {
        provider == .codex ? store.codex : store.claude
    }

    var body: some View {
        let providers = Self.visibleProviders(store: store)
        let size = Self.panelSize(providerCount: providers.count, edge: edge)
        Group {
            if edge.isHorizontal {
                HStack(spacing: 0) {
                    ForEach(providers, id: \.self) { provider in
                        cell(for: provider, state: Self.state(for: provider, in: store))
                    }
                }
                .padding(.horizontal, Self.contentEdgeInset)
            } else {
                VStack(spacing: 0) {
                    ForEach(providers, id: \.self) { provider in
                        cell(for: provider, state: Self.state(for: provider, in: store))
                    }
                }
                .padding(.vertical, Self.contentEdgeInset)
            }
        }
        .frame(width: size.width, height: size.height)
        // Fully opaque, not just dark: this view lives in RailPanel, a transparent
        // borderless window with no system material or blur behind it — any opacity here
        // lets the desktop and whatever window is behind it show through the rail.
        .background(backingShape.fill(Color.black))
        // Popping loose from the edge is quick; settling back onto it is a touch springier,
        // so the dock reads as the shape landing rather than just stopping. `value:` keys
        // the animation to the direction of travel, since RailShape's own `animatableData`
        // conformance is what makes either curve interpolate the radii frame-by-frame at all.
        .animation(
            presentation.isFloating ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8),
            value: presentation.isFloating
        )
    }

    /// The rail's dark backing: flush with the screen edge on the docked side — flowing into
    /// it through concave fillets rather than meeting it as a straight seam — and rounded on
    /// the free end, so the free end reads as a distinct floating pill while the docked side
    /// reads as growing out of the screen. While `presentation.isFloating`, the fillets
    /// collapse to nothing while both ends round to half the band's thickness, so the same
    /// contour instead reads as a standalone capsule with no fixed edge. Built once
    /// here so the fill and the stroke never disagree about the shape.
    private var backingShape: RailShape {
        presentation.isFloating
            ? RailShape(
                edge: edge,
                cornerRadius: floatingCornerRadius,
                filletRadius: 0,
                dockedCornerRadius: floatingCornerRadius
            )
            : RailShape(
                edge: edge,
                cornerRadius: Self.cornerRadius,
                filletRadius: Self.filletRadius,
                dockedCornerRadius: 0
            )
    }

    /// Half the band's cross-thickness — `cellHeight` for a horizontal (top/bottom) rail,
    /// `cellWidth` for a vertical (side) one, the same orientation split `panelSize` and the
    /// stack layout above already use. Rounding the free end by this much, with the docked
    /// fillets gone, is what turns the contour into a capsule while floating.
    private var floatingCornerRadius: CGFloat {
        (edge.isHorizontal ? Self.cellHeight : Self.cellWidth) / 2
    }

    private func cell(for provider: QuotaProvider, state: ProviderState) -> some View {
        VStack(spacing: 4) {
            QuotaRing(window: state.quota?.headlineWindow, provider: provider)
            Text(percentText(state.quota?.headlineWindow))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(state.quota?.headlineWindow == nil ? Color.white.opacity(0.5) : Color.white)
        }
        .frame(width: Self.cellWidth, height: Self.cellHeight)
        // The "!" sits above the ring rather than replacing anything — the numbers stay
        // exactly as they are, whether stale or fresh.
        .overlay(alignment: .topTrailing) {
            if hasProblem(state) {
                Text("!")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.trailing, 4)
                    .padding(.top, 2)
            }
        }
    }

    private func hasProblem(_ state: ProviderState) -> Bool {
        state.lastError != nil || state.isStale
    }

    private func percentText(_ window: QuotaWindow?) -> String {
        guard let window else { return "—" }
        return "\(window.displayedPercent)%"
    }
}
