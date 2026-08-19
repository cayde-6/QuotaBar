import SwiftUI

/// One quota window's column within a provider card (e.g. "5 HOUR" or "WEEKLY").
struct QuotaWindowColumn: View {
    let title: String
    let window: QuotaWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            if let window {
                Text("\(window.displayedPercent)%")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(window.level.menuColor)
                if let resetText = DateFormatting.resetDescription(for: window.resetsAt) {
                    Text(resetText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No data")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
