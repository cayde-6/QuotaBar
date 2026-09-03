import SwiftUI

/// One provider's card in the popover: icon, name, and its quota windows (or an error).
struct ProviderCard: View {
    let provider: QuotaProvider
    let state: ProviderState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(provider.iconName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.secondary)

                Text(provider.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if state.quota == nil, let error = state.lastError {
                // Wraps up to a few lines, then truncates, with the whole message available
                // on hover — card width is fixed by the equal-width HStack above, and an
                // unrecognized error (codex's raw RPC text, say) must never take it over.
                Text(error.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                    .help(error.message)
            } else {
                if let warning = warningText(for: state) {
                    Text("⚠︎ \(warning)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                        .help(warning)
                }
                HStack(alignment: .top, spacing: 12) {
                    QuotaWindowColumn(title: "5 HOUR", window: state.quota?.shortWindow)
                    QuotaWindowColumn(title: "WEEKLY", window: state.quota?.weeklyWindow)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }

    /// Message shown above a provider's window columns when the data is present but
    /// suspect (stale or the last refresh attempt failed).
    private func warningText(for state: ProviderState) -> String? {
        guard state.quota != nil else { return nil }
        if let error = state.lastError { return error.message }
        if state.isStale { return "Data is stale" }
        return nil
    }
}
