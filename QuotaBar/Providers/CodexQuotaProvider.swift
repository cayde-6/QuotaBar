import Foundation

/// Fetches Codex rate-limit data from the local `codex app-server` process via JSON-RPC 2.0
/// over stdin/stdout, one JSON object per line.
actor CodexQuotaProvider {
    private let timeout: TimeInterval = 25

    func fetch() async throws -> ProviderQuota {
        let process = Process()
        // Launched through a login shell so it inherits the user's real PATH — a GUI app
        // starts with a minimal PATH and would not find `codex` or `node` otherwise.
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec codex app-server"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stderrCollector = StderrCollector()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                stderrCollector.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw QuotaError.cliNotFound
        }

        defer {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            // Never leak the process, on any exit path (success, error, timeout).
            if process.isRunning {
                process.terminate()
            }
        }

        do {
            return try await withThrowingTaskGroup(of: ProviderQuota.self) { group in
                group.addTask {
                    try await self.talk(stdin: stdinPipe.fileHandleForWriting, stdout: stdoutPipe.fileHandleForReading)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(self.timeout))
                    process.terminate()
                    throw QuotaError.network("timeout")
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch {
            // Require "codex" alongside "not found" so unrelated shell startup noise
            // (e.g. "nvm: command not found" from .zshenv) doesn't get misread as this.
            let stderrText = stderrCollector.text.lowercased()
            if stderrText.contains("not found") && stderrText.contains("codex") {
                throw QuotaError.cliNotFound
            }
            if !process.isRunning, process.terminationStatus == 127 {
                throw QuotaError.cliNotFound
            }
            throw error
        }
    }

    // MARK: - JSON-RPC exchange

    private func talk(stdin: FileHandle, stdout: FileHandle) async throws -> ProviderQuota {
        try write([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": ["clientInfo": ["name": "QuotaBar", "version": "1.0.0"]]
        ], to: stdin)

        var sentSecondRequest = false

        for try await line in stdout.bytes.lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue // ignore stray/invalid lines
            }

            if !sentSecondRequest {
                guard matchesID(object, 1) else { continue } // ignore unrelated notifications

                if let errorObject = object["error"] as? [String: Any] {
                    throw classifyRPCError(errorObject)
                }

                try write(["jsonrpc": "2.0", "method": "initialized"], to: stdin)
                try write(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": NSNull()], to: stdin)
                sentSecondRequest = true
                continue
            }

            guard matchesID(object, 2) else { continue }

            if let errorObject = object["error"] as? [String: Any] {
                throw classifyRPCError(errorObject)
            }
            guard let result = object["result"] as? [String: Any] else {
                throw QuotaError.malformedResponse
            }
            return try parseRateLimits(result)
        }

        throw QuotaError.malformedResponse // stdout closed before we got an answer
    }

    private func write(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A) // newline-delimited JSON
        try handle.write(contentsOf: data)
    }

    private func matchesID(_ object: [String: Any], _ id: Int) -> Bool {
        (object["id"] as? Int) == id
    }

    private func classifyRPCError(_ error: [String: Any]) -> QuotaError {
        let message = (error["message"] as? String ?? "").lowercased()
        let authKeywords = ["auth", "login", "sign in", "unauthorized", "401"]
        if authKeywords.contains(where: { message.contains($0) }) {
            return .notAuthenticated
        }
        return .malformedResponse
    }

    // MARK: - Rate limit parsing

    private struct RawWindow {
        let usedPercent: Double
        let windowDurationMins: Int64?
        let resetsAt: Int64?
    }

    private func parseWindow(_ dict: [String: Any]) throws -> RawWindow {
        guard let usedPercent = (dict["usedPercent"] as? NSNumber)?.doubleValue else {
            throw QuotaError.malformedResponse
        }
        let windowDurationMins = (dict["windowDurationMins"] as? NSNumber)?.int64Value
        let resetsAt = (dict["resetsAt"] as? NSNumber)?.int64Value
        return RawWindow(usedPercent: usedPercent, windowDurationMins: windowDurationMins, resetsAt: resetsAt)
    }

    /// Classifies the primary/secondary windows into short (5h) and weekly buckets by duration,
    /// not by position — on this CLI version `primary` can hold the weekly window. When both
    /// windows are present, the longest always wins `weekly`, but the short slot never accepts
    /// a window longer than a day (`windowDurationMins > 1440`): if even the shorter of the two
    /// windows is week/month-scale, there is no real "5 hour" window to show, and a mislabeled
    /// weekly or monthly number under that heading is worse than an honest "No data" — so
    /// `short` comes back nil and the "5 hour" row in MenuView shows a placeholder instead.
    private func classify(primary: RawWindow?, secondary: RawWindow?) -> (short: RawWindow?, weekly: RawWindow?) {
        let windows = [primary, secondary].compactMap { $0 }

        switch windows.count {
        case 0:
            return (nil, nil)
        case 1:
            let window = windows[0]
            if let mins = window.windowDurationMins {
                return mins <= 1440 ? (window, nil) : (nil, window)
            }
            // Legacy fallback when duration is missing: primary is short, secondary is weekly.
            return primary != nil ? (window, nil) : (nil, window)
        default:
            // Two windows — `a` is primary, `b` is secondary (the only way to reach this
            // branch with exactly two RawWindows). Handled as three explicit cases rather
            // than "sort with missing durations pushed last": that scheme misclassified a
            // pair where only one window has a duration, since the nil-duration window
            // (which can easily be the real 5-hour window) always lost the sort and got
            // discarded instead of falling into the other slot.
            let a = windows[0]
            let b = windows[1]

            switch (a.windowDurationMins, b.windowDurationMins) {
            case let (aMins?, bMins?):
                // Both known: shorter wins `short` (but only if it's actually <=1440),
                // longer wins `weekly`. Equal durations tie toward position (a, i.e.
                // primary, is treated as the "shorter" one) so the result is deterministic.
                let (shorter, longer) = aMins <= bMins ? (a, b) : (b, a)
                let short = (shorter.windowDurationMins ?? 0) <= 1440 ? shorter : nil
                return (short, longer)
            case let (aMins?, nil):
                // Only `a` has a duration: classify it by threshold, `b` takes the other slot.
                return aMins <= 1440 ? (a, b) : (b, a)
            case let (nil, bMins?):
                return bMins <= 1440 ? (b, a) : (a, b)
            case (nil, nil):
                // Legacy fallback when neither has a duration: primary short, secondary weekly.
                return (a, b)
            }
        }
    }

    private func extractRateLimits(_ result: [String: Any]) -> [String: Any]? {
        if let rateLimits = result["rateLimits"] as? [String: Any] {
            return rateLimits
        }
        if let byLimitId = result["rateLimitsByLimitId"] as? [String: Any] {
            if let codex = byLimitId["codex"] as? [String: Any] {
                return codex
            }
            // Dictionary iteration order is unspecified — pick the lexicographically
            // smallest key so repeated calls with the same data agree with each other.
            if let smallestKey = byLimitId.keys.sorted().first, let value = byLimitId[smallestKey] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private func parseRateLimits(_ result: [String: Any]) throws -> ProviderQuota {
        guard let rateLimits = extractRateLimits(result) else {
            throw QuotaError.malformedResponse
        }

        let primaryDict = rateLimits["primary"] as? [String: Any]
        let secondaryDict = rateLimits["secondary"] as? [String: Any]

        // Both windows being absent is a normal state for a fresh account with zero
        // consumption, not an auth failure — real auth errors are caught in
        // classifyRPCError before we ever get here. Just report "no data" for both.
        let primary = try primaryDict.map(parseWindow)
        let secondary = try secondaryDict.map(parseWindow)
        let (shortRaw, weeklyRaw) = classify(primary: primary, secondary: secondary)

        func makeWindow(_ raw: RawWindow?) -> QuotaWindow? {
            guard let raw else { return nil }
            let resetsAt = raw.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            return QuotaWindow(utilization: raw.usedPercent, resetsAt: resetsAt)
        }

        return ProviderQuota(shortWindow: makeWindow(shortRaw), weeklyWindow: makeWindow(weeklyRaw), fetchedAt: Date())
    }
}

/// Thread-safe accumulator for stderr output, used only to classify failures
/// (e.g. "command not found"). Never logged or shown verbatim to the user.
private final class StderrCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
