import SwiftUI

/// Rail ring color for a provider. Distinct from `QuotaLevel.menuColor` — this is the
/// provider's brand color, fixed regardless of how much quota remains, whereas
/// `menuColor` still drives the popover and the menu bar and changes with the level.
extension QuotaProvider {
    var accentColor: Color {
        switch self {
        case .codex: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .claude: return Color(red: 0.91, green: 0.34, blue: 0.16)
        }
    }
}
