import AppKit
import Foundation
import Testing

@Suite("Provider freshness")
struct ProviderFreshnessTests {
    @Test("quota expires at the selected refresh interval", arguments: [1, 5, 15, 30, 60])
    func ageBoundary(minutes: Int) {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var state = ProviderState(quota: quota(fetchedAt: fetchedAt))
        let deadline = fetchedAt.addingTimeInterval(TimeInterval(minutes) * 60)

        #expect(state.freshnessDeadline(refreshIntervalMinutes: minutes) == deadline)
        #expect(!state.isStale(at: deadline.addingTimeInterval(-1), refreshIntervalMinutes: minutes))
        #expect(state.isStale(at: deadline, refreshIntervalMinutes: minutes))
        #expect(state.isStale(at: deadline.addingTimeInterval(1), refreshIntervalMinutes: minutes))

        state.quota = quota(fetchedAt: deadline)
        #expect(!state.isStale(at: deadline, refreshIntervalMinutes: minutes))
    }

    @Test("changing the interval immediately re-evaluates existing data")
    func intervalChanges() {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let state = ProviderState(quota: quota(fetchedAt: fetchedAt))
        let now = fetchedAt.addingTimeInterval(20 * 60)

        #expect(state.isStale(at: now, refreshIntervalMinutes: 5))
        #expect(!state.isStale(at: now, refreshIntervalMinutes: 60))
        #expect(state.isStale(at: now, refreshIntervalMinutes: 1))
    }

    @Test("missing quota is stale and has no deadline to schedule")
    func missingQuota() {
        let state = ProviderState()
        #expect(state.isStale(at: Date(), refreshIntervalMinutes: 60))
        #expect(state.freshnessDeadline(refreshIntervalMinutes: 60) == nil)
    }

    private func quota(fetchedAt: Date) -> ProviderQuota {
        ProviderQuota(
            shortWindow: QuotaWindow(utilization: 25, resetsAt: nil),
            weeklyWindow: nil,
            planWindow: nil,
            fetchedAt: fetchedAt
        )
    }
}

@Suite("Freshness deadlines")
@MainActor
struct FreshnessDeadlineTests {
    @Test("a deadline fires once without triggering network polling")
    func oneShotCheck() async throws {
        let scheduler = RefreshScheduler()
        var dates: [Date] = []
        var networkRequests = 0
        scheduler.onFreshnessCheck = { dates.append($0) }
        scheduler.onTick = { _ in networkRequests += 1 }
        scheduler.startAutoRefreshLoop(intervalMinutes: 60)
        let deadline = Date().addingTimeInterval(0.01)
        scheduler.scheduleFreshnessCheck(at: deadline)
        #expect(dates.isEmpty)

        for _ in 0..<100 where dates.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(40))

        #expect(dates.count == 1)
        let firedAt = try #require(dates.first)
        #expect(firedAt >= deadline)
        #expect(networkRequests == 0)
    }

    @Test("removing the deadline cancels the pending check")
    func cancelDeadline() async throws {
        let scheduler = RefreshScheduler()
        var checks = 0
        scheduler.onFreshnessCheck = { _ in checks += 1 }
        scheduler.scheduleFreshnessCheck(at: Date().addingTimeInterval(0.02))
        scheduler.scheduleFreshnessCheck(at: nil)
        try await Task.sleep(for: .milliseconds(60))

        #expect(checks == 0)
    }

    @Test("a later deadline replaces the earlier one")
    func rescheduleDeadline() async throws {
        let scheduler = RefreshScheduler()
        var dates: [Date] = []
        scheduler.onFreshnessCheck = { dates.append($0) }
        scheduler.scheduleFreshnessCheck(at: Date().addingTimeInterval(0.01))
        let newDeadline = Date().addingTimeInterval(0.1)
        scheduler.scheduleFreshnessCheck(at: newDeadline)

        for _ in 0..<100 where dates.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(dates.count == 1)
        let firedAt = try #require(dates.first)
        #expect(firedAt >= newDeadline)
    }

    @Test("wake checks age even when a recent request skips network polling")
    func wakeUpdatesClock() async throws {
        let scheduler = RefreshScheduler()
        var clockTicks = 0
        var networkRequests = 0
        scheduler.onFreshnessCheck = { _ in clockTicks += 1 }
        scheduler.onTick = { _ in networkRequests += 1 }
        scheduler.mostRecentAttempt = { Date() }
        scheduler.observeSystemWake()

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<100 where clockTicks == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(clockTicks == 1)
        #expect(networkRequests == 0)
    }

    @Test("a pending deadline does not retain its scheduler")
    func deadlineLifetime() async {
        var scheduler: RefreshScheduler? = RefreshScheduler()
        let schedulerIsAlive = { [weak scheduler] in scheduler != nil }
        scheduler?.scheduleFreshnessCheck(at: Date().addingTimeInterval(3600))
        await Task.yield()
        scheduler = nil

        #expect(!schedulerIsAlive())
    }
}
