import Foundation
import Testing

private func window(_ usedPercent: Double, durationMins: Int64? = nil, resetsAt: Int64? = nil) -> RawWindow {
    RawWindow(usedPercent: usedPercent, windowDurationMins: durationMins, resetsAt: resetsAt)
}

@Suite("CodexRateLimitParser.classify")
struct CodexRateLimitParserClassifyTests {
    @Test("no windows at all")
    func noWindows() {
        let result = CodexRateLimitParser.classify(primary: nil, secondary: nil)
        #expect(result.short == nil)
        #expect(result.weekly == nil)
    }

    @Test("one window with a short duration lands in short")
    func oneWindowShortDuration() {
        let result = CodexRateLimitParser.classify(primary: window(11, durationMins: 300), secondary: nil)
        #expect(result.short?.usedPercent == 11)
        #expect(result.weekly == nil)
    }

    @Test("one window with a week-scale duration lands in weekly, not short")
    func oneWindowWeekScaleDuration() {
        let result = CodexRateLimitParser.classify(primary: window(11, durationMins: 10080), secondary: nil)
        #expect(result.short == nil)
        #expect(result.weekly?.usedPercent == 11)
    }

    @Test("one window with no duration, passed as primary")
    func oneWindowNoDurationAsPrimary() {
        let result = CodexRateLimitParser.classify(primary: window(11), secondary: nil)
        #expect(result.short?.usedPercent == 11)
        #expect(result.weekly == nil)
    }

    @Test("one window with no duration, passed as secondary")
    func oneWindowNoDurationAsSecondary() {
        let result = CodexRateLimitParser.classify(primary: nil, secondary: window(11))
        #expect(result.short == nil)
        #expect(result.weekly?.usedPercent == 11)
    }

    @Test("two windows, both durations known: shorter wins short, longer wins weekly")
    func twoWindowsBothKnown() {
        // Primary holds the LONGER duration here, to prove classification goes by
        // duration, not by position.
        let result = CodexRateLimitParser.classify(
            primary: window(11, durationMins: 10080),
            secondary: window(22, durationMins: 300)
        )
        #expect(result.short?.usedPercent == 22)
        #expect(result.weekly?.usedPercent == 11)
    }

    @Test("two windows both known but the shorter one is still longer than 1440 minutes")
    func twoWindowsBothKnownButShorterStillOverThreshold() {
        let result = CodexRateLimitParser.classify(
            primary: window(11, durationMins: 2000),
            secondary: window(22, durationMins: 3000)
        )
        #expect(result.short == nil)
        #expect(result.weekly?.usedPercent == 22)
    }

    @Test("equal durations resolve deterministically toward primary as short")
    func equalDurationsResolveDeterministically() {
        let result = CodexRateLimitParser.classify(
            primary: window(11, durationMins: 300),
            secondary: window(22, durationMins: 300)
        )
        #expect(result.short?.usedPercent == 11)
        #expect(result.weekly?.usedPercent == 22)
    }

    @Test("only primary has a duration (short-eligible): secondary is not discarded")
    func onlyPrimaryDurationShortEligible() {
        let result = CodexRateLimitParser.classify(
            primary: window(11, durationMins: 300),
            secondary: window(22)
        )
        #expect(result.short?.usedPercent == 11)
        #expect(result.weekly?.usedPercent == 22)
    }

    @Test("only primary has a duration (too long for short): secondary is not discarded")
    func onlyPrimaryDurationTooLong() {
        let result = CodexRateLimitParser.classify(
            primary: window(11, durationMins: 2000),
            secondary: window(22)
        )
        #expect(result.short?.usedPercent == 22)
        #expect(result.weekly?.usedPercent == 11)
    }

    @Test("only secondary has a duration (short-eligible): primary is not discarded")
    func onlySecondaryDurationShortEligible() {
        let result = CodexRateLimitParser.classify(
            primary: window(11),
            secondary: window(22, durationMins: 300)
        )
        #expect(result.short?.usedPercent == 22)
        #expect(result.weekly?.usedPercent == 11)
    }

    @Test("only secondary has a duration (too long for short): primary is not discarded")
    func onlySecondaryDurationTooLong() {
        let result = CodexRateLimitParser.classify(
            primary: window(11),
            secondary: window(22, durationMins: 2000)
        )
        #expect(result.short?.usedPercent == 11)
        #expect(result.weekly?.usedPercent == 22)
    }
}

@Suite("CodexRateLimitParser.extractRateLimits")
struct CodexRateLimitParserExtractTests {
    @Test("prefers rateLimits over rateLimitsByLimitId")
    func prefersRateLimits() {
        let result: [String: Any] = [
            "rateLimits": ["marker": "rateLimits"],
            "rateLimitsByLimitId": ["codex": ["marker": "codex"]],
        ]
        let extracted = CodexRateLimitParser.extractRateLimits(result)
        #expect(extracted?["marker"] as? String == "rateLimits")
    }

    @Test("falls back to rateLimitsByLimitId.codex")
    func fallsBackToCodexKey() {
        let result: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": ["marker": "codex"],
                "other": ["marker": "other"],
            ],
        ]
        let extracted = CodexRateLimitParser.extractRateLimits(result)
        #expect(extracted?["marker"] as? String == "codex")
    }

    @Test("with no codex key, picks the lexicographically smallest key, repeatably")
    func picksLexicographicallySmallestKey() {
        let result: [String: Any] = [
            "rateLimitsByLimitId": [
                "zzz": ["marker": "zzz"],
                "aaa": ["marker": "aaa"],
                "mmm": ["marker": "mmm"],
            ],
        ]
        for _ in 0..<5 {
            let extracted = CodexRateLimitParser.extractRateLimits(result)
            #expect(extracted?["marker"] as? String == "aaa")
        }
    }

    @Test("returns nil when neither key is present")
    func returnsNilWhenNeitherPresent() {
        #expect(CodexRateLimitParser.extractRateLimits([:]) == nil)
        #expect(CodexRateLimitParser.extractRateLimits(["unrelated": 1]) == nil)
    }
}

@Suite("CodexRateLimitParser.parseRateLimits")
struct CodexRateLimitParserParseTests {
    @Test("a realistic payload produces the expected short and weekly windows")
    func realisticPayload() throws {
        let shortReset: Int64 = 1_700_000_000
        let weeklyReset: Int64 = 1_700_600_000
        let payload: [String: Any] = [
            "rateLimits": [
                "primary": [
                    "usedPercent": 0,
                    "windowDurationMins": 300,
                    "resetsAt": shortReset,
                ],
                "secondary": [
                    "usedPercent": 4,
                    "windowDurationMins": 10080,
                    "resetsAt": weeklyReset,
                ],
            ],
        ]
        let quota = try CodexRateLimitParser.parseRateLimits(payload)

        #expect(quota.shortWindow?.remainingPercentage == 100)
        #expect(quota.shortWindow?.resetsAt == Date(timeIntervalSince1970: TimeInterval(shortReset)))

        #expect(quota.weeklyWindow?.remainingPercentage == 96)
        #expect(quota.weeklyWindow?.resetsAt == Date(timeIntervalSince1970: TimeInterval(weeklyReset)))
    }

    @Test("a window missing usedPercent throws malformedResponse")
    func missingUsedPercentThrows() {
        let payload: [String: Any] = [
            "rateLimits": [
                "primary": ["windowDurationMins": 300],
            ],
        ]
        #expect(throws: QuotaError.malformedResponse) {
            try CodexRateLimitParser.parseRateLimits(payload)
        }
    }

    @Test("both windows absent is not an error and yields nil windows")
    func bothWindowsAbsent() throws {
        let payload: [String: Any] = ["rateLimits": [:]]
        let quota = try CodexRateLimitParser.parseRateLimits(payload)
        #expect(quota.shortWindow == nil)
        #expect(quota.weeklyWindow == nil)
    }
}
