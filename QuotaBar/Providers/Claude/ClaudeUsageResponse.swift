import Foundation

/// Parses the response body of Claude's `/api/oauth/usage` endpoint.
enum ClaudeUsageResponse {
    static func parseUsage(_ data: Data) throws -> ProviderQuota {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.malformedResponse
        }

        let shortWindow = parseWindow(object["five_hour"])
        let weeklyWindow = parseWindow(object["seven_day"])

        guard shortWindow != nil || weeklyWindow != nil else {
            throw QuotaError.malformedResponse
        }

        return ProviderQuota(shortWindow: shortWindow, weeklyWindow: weeklyWindow, fetchedAt: Date())
    }

    static func parseWindow(_ raw: Any?) -> QuotaWindow? {
        guard let dict = raw as? [String: Any],
              let utilization = (dict["utilization"] as? NSNumber)?.doubleValue else {
            return nil
        }
        let resetsAt = (dict["resets_at"] as? String).flatMap(parseDate)
        return QuotaWindow(utilization: utilization, resetsAt: resetsAt)
    }

    /// Tries progressively looser ISO-8601 parsers, since the API's fractional-seconds
    /// format isn't accepted by every formatter. Falls back to a nil reset date rather
    /// than dropping the whole window — the percentage matters more than the date.
    static func parseDate(_ string: String) -> Date? {
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFraction.date(from: string) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }

        let formatterWithFraction = DateFormatter()
        formatterWithFraction.locale = Locale(identifier: "en_US_POSIX")
        formatterWithFraction.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        if let date = formatterWithFraction.date(from: string) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.date(from: string)
    }
}
