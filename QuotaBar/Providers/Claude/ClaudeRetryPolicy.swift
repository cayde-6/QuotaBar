import Foundation

/// Delay automatic usage checks after Anthropic responds with HTTP 429. A zero
/// Retry-After has been observed even when the endpoint keeps rejecting requests.
enum ClaudeRetryPolicy {
    static let minimumPause: TimeInterval = 15 * 60

    static func delay(retryAfter: String?, now: Date) -> TimeInterval {
        guard let value = retryAfter?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return minimumPause
        }

        if let seconds = TimeInterval(value), seconds.isFinite {
            return max(minimumPause, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        if let date = formatter.date(from: value) {
            return max(minimumPause, date.timeIntervalSince(now))
        }
        return minimumPause
    }
}
