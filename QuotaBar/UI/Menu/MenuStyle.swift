import SwiftUI

/// How the popover is dressed, which depends on which surface opened it.
enum MenuStyle: Sendable {
    case system   // menu bar: the existing translucent look
    case dark     // rail widget: black, to match the widget it hangs off
}
