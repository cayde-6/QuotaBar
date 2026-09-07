import SwiftUI

/// Floating readout: one ring-and-percentage cell per set-up provider, laid out as a
/// column when docked to a side edge or a row when docked to top/bottom. Unlike
/// StatusBarView, this is a live SwiftUI hierarchy — it's hosted directly, never
/// rasterized — so it updates and animates on its own as `store` changes.
struct RailView: View {
    let store: QuotaStore
    let edge: RailEdge

    static let cellWidth: CGFloat = 70
    static let cellHeight: CGFloat = 72
    static let cornerRadius: CGFloat = 16

    /// Codex first, then Claude — same order as the menu bar and popover — excluding any
    /// provider that isn't set up on this machine (`ProviderState.isMissing`). The
    /// controller calls this exact method to size and position the panel, so it and the
    /// view can never disagree about which providers are shown.
    static func visibleProviders(store: QuotaStore) -> [QuotaProvider] {
        [.codex, .claude].filter { !state(for: $0, in: store).isMissing(for: $0) }
    }

    /// The panel's size for `edge`: a single-cell-wide column of `providerCount` cells on
    /// a side edge, or a single-cell-tall row of `providerCount` cells on top/bottom.
    static func panelSize(providerCount: Int, edge: RailEdge) -> CGSize {
        edge.isHorizontal
            ? CGSize(width: cellWidth * CGFloat(providerCount), height: cellHeight)
            : CGSize(width: cellWidth, height: cellHeight * CGFloat(providerCount))
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
            } else {
                VStack(spacing: 0) {
                    ForEach(providers, id: \.self) { provider in
                        cell(for: provider, state: Self.state(for: provider, in: store))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        // Fully opaque, not just dark: this view lives in RailPanel, a transparent
        // borderless window with no system material or blur behind it — any opacity here
        // lets the desktop and whatever window is behind it show through the rail.
        .background(backingShape.fill(Color.black))
        .overlay(backingShape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }

    /// The rail's dark backing, square on the side docked to the screen edge and rounded
    /// on the free end — so the docked side reads as flush with the screen while the free
    /// end reads as a distinct floating pill, not a continuation of the screen's edge.
    /// Built once here so the fill and the stroke never disagree about the shape.
    private var backingShape: UnevenRoundedRectangle {
        switch edge {
        case .bottom:
            return UnevenRoundedRectangle(
                topLeadingRadius: Self.cornerRadius, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: Self.cornerRadius
            )
        case .left:
            return UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0,
                bottomTrailingRadius: Self.cornerRadius, topTrailingRadius: Self.cornerRadius
            )
        case .right:
            return UnevenRoundedRectangle(
                topLeadingRadius: Self.cornerRadius, bottomLeadingRadius: Self.cornerRadius,
                bottomTrailingRadius: 0, topTrailingRadius: 0
            )
        }
    }

    private func cell(for provider: QuotaProvider, state: ProviderState) -> some View {
        VStack(spacing: 4) {
            QuotaRing(window: state.quota?.shortWindow, provider: provider)
            Text(percentText(state.quota?.shortWindow))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(state.quota?.shortWindow == nil ? Color.white.opacity(0.5) : Color.white)
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
