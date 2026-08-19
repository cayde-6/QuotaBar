import SwiftUI

/// Color logic for the menu bar's rendered image. Dynamic system colors aren't reliable
/// inside ImageRenderer, which renders outside of any window's appearance context, so
/// every color here is a concrete, precomputed value driven by an explicit `isDark` flag.
struct StatusBarPalette {
    let isDark: Bool

    /// Icon, "!", and the "—" placeholder aren't level-colored — they read as plain
    /// foreground content, matching a template image's usual look.
    var neutralColor: Color {
        isDark ? .white : .black
    }

    func percentColor(_ window: QuotaWindow?) -> Color {
        guard let window else { return neutralColor }
        return color(for: window.level)
    }

    /// Two hand-picked shades per level — one for the near-black dark menu bar, one for
    /// the light one. A straight system green/yellow/red would look identical in both,
    /// which reads fine on dark but is nearly invisible (yellow) or low-contrast
    /// (green/red) against a light menu bar, so the light variants are darker/more
    /// saturated on purpose.
    func color(for level: QuotaLevel) -> Color {
        switch level {
        case .healthy:
            return isDark
                ? Color(red: 0.20, green: 0.85, blue: 0.35)
                : Color(red: 0.00, green: 0.50, blue: 0.15)
        case .warning:
            return isDark
                ? Color(red: 1.00, green: 0.80, blue: 0.10)
                : Color(red: 0.55, green: 0.40, blue: 0.00)
        case .critical:
            return isDark
                ? Color(red: 1.00, green: 0.30, blue: 0.30)
                : Color(red: 0.75, green: 0.05, blue: 0.05)
        }
    }
}
