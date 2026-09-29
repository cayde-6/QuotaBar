import Foundation
import Testing

@Suite("Claude usage rate-limit backoff")
struct ClaudeRateLimitTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("missing and zero Retry-After values pause automatic requests")
    func minimumPause() {
        #expect(ClaudeRetryPolicy.delay(retryAfter: nil, now: now) == 900)
        #expect(ClaudeRetryPolicy.delay(retryAfter: "0", now: now) == 900)
        #expect(ClaudeRetryPolicy.delay(retryAfter: "invalid", now: now) == 900)
    }

    @Test("a longer Retry-After delay is respected")
    func secondsDelay() {
        #expect(ClaudeRetryPolicy.delay(retryAfter: "1800", now: now) == 1800)
    }

    @Test("an HTTP-date Retry-After delay is respected")
    func dateDelay() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let retryAfter = formatter.string(from: now.addingTimeInterval(3600))

        #expect(ClaudeRetryPolicy.delay(retryAfter: retryAfter, now: now) == 3600)
    }
}
