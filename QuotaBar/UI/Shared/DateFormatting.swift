import Foundation

/// Date/time text formatting shared by the popover's footer and provider cards.
/// The formatters are built fresh on each call, rather than cached, so a locale change or
/// a 12/24-hour toggle in System Settings is picked up immediately without a restart. The
/// popover only renders on click, not continuously, so the cost of rebuilding is negligible.
enum DateFormatting {
    static func lastUpdatedText(_ date: Date?) -> String {
        guard let date else { return "Updated never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: date))"
    }

    /// Shortened for the narrower card columns: no "Resets" prefix (the heading above it
    /// already says which window), and a short weekday ("Sat 03:00" instead of
    /// "Resets Saturday 14:00").
    static func resetDescription(for date: Date?) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return nil }

        if interval < 24 * 3600 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return formatter.string(from: date)
    }
}
