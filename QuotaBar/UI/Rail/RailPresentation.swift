import SwiftUI

/// Drag-time presentation state for the widget, shared between the controller that
/// drives it and the SwiftUI view that draws it. An observable object rather than a
/// value passed into RailView: the controller replaces the hosting view's rootView on
/// other occasions (edge changes), and a value swapped in that way redraws instantly
/// instead of animating.
@MainActor @Observable final class RailPresentation {
    var isFloating = false
}
