import SwiftUI

// MARK: - Liquid Glass helpers

/// Card background: real Liquid Glass on macOS 26+, a plain system material otherwise.
/// One modifier instead of an `#available` branch at every card, and neutral either way
/// — no level-color tinting, color lives only in the percentage text.
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content.background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// Glass button chrome on macOS 26+; the system default style otherwise.
struct GlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content
        }
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }

    func glassButton() -> some View {
        modifier(GlassButton())
    }
}
