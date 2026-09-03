import Foundation

/// One JSON-RPC 2.0 conversation with a codex app-server process over stdin/stdout,
/// newline-delimited JSON per message: initialize → initialized → account/rateLimits/read.
struct CodexAppServerSession {
    // The one failure whose reason lives only in the child's stderr, not in an RPC message —
    // the provider matches on this exact detail to decide whether appending the stderr tail
    // adds information. Every other .unexpectedFailure already carries codex's own message,
    // and gluing a tracing line onto that only adds noise.
    static let exitedWithoutAnsweringDetail = "codex app-server exited without answering"

    func talk(stdin: FileHandle, stdout: FileHandle) async throws -> ProviderQuota {
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
            return try CodexRateLimitParser.parseRateLimits(result)
        }

        // CodexQuotaProvider matches this detail exactly to decide whether to append the
        // stderr tail, so it must reach that comparison unwrapped and unprefixed.
        throw QuotaError.unexpectedFailure(Self.exitedWithoutAnsweringDetail)
    }

    private func write(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A) // newline-delimited JSON
        try handle.write(contentsOf: data)
    }

    private func matchesID(_ object: [String: Any], _ id: Int) -> Bool {
        (object["id"] as? Int) == id
    }

    // Not private: unit-tested directly from CodexAppServerSessionTests.
    func classifyRPCError(_ error: [String: Any]) -> QuotaError {
        let originalMessage = error["message"] as? String ?? ""
        let message = originalMessage.lowercased()

        // codex app-server reports a lost backend connection (commonly the post-wake
        // auto-refresh firing before Wi-Fi is back) as a plain JSON-RPC error rather than
        // a distinct error code, so the only way to recognize it is the message text. This
        // has to run before the auth check below: its markers are more specific, and a
        // network failure whose URL happens to contain "auth" (e.g. auth.openai.com) would
        // otherwise be misreported as "Not signed in".
        if message.contains("timed out") || message.contains("timeout") {
            return .network("timeout")
        }
        let unreachableKeywords = ["error sending request", "connect", "network", "offline", "unreachable", "dns", "resolve"]
        if unreachableKeywords.contains(where: { message.contains($0) }) {
            return .network("unreachable")
        }

        // codex renders a failed backend call with the HTTP status embedded in the message
        // (e.g. "unexpected status 500 Internal Server Error", or "GET …: 403 Forbidden").
        // Reporting that status keeps the card to one short line AND says something
        // actionable, and deliberately mirrors how ClaudeQuotaProvider words the identical
        // situation (401/403 → a specific case, otherwise "HTTP <code>") instead of
        // inventing a second vocabulary for the same failure shape. This has to run before
        // the auth check below: authKeywords matches the bare substring "auth", so a 500
        // returned by a URL on auth.openai.com would otherwise be reported as "Not signed
        // in" — reading the status first is what makes that case come out right. 401 is
        // mapped back to .notAuthenticated on purpose, to preserve the behavior the "401"
        // keyword already had; 403 becomes .unauthorized ("Access denied") because it's a
        // permission/plan problem, not a missing login.
        if let statusCode = httpStatusCode(in: message) {
            switch statusCode {
            case 401: return .notAuthenticated
            case 403: return .unauthorized
            default: return .network("HTTP \(statusCode)")
            }
        }

        let authKeywords = ["auth", "login", "sign in", "unauthorized", "401"]
        if authKeywords.contains(where: { message.contains($0) }) {
            return .notAuthenticated
        }

        // A rate-limit read failure with no status attached (codex's own "failed to fetch
        // codex rate limits: no snapshots returned" is a real example) intentionally falls
        // through to here rather than being forced into a category we can't back up: the
        // card now bounds long messages with .lineLimit, so an honest sentence from codex
        // beats a guessed classification.
        //
        // The result parsed fine as valid JSON-RPC, so claiming the response format
        // changed (.malformedResponse) would be wrong; .unexpectedFailure exists for
        // exactly this — a failure we can't attribute to a known category — and keeps
        // codex's own message visible instead of hiding it behind a generic label.
        return .unexpectedFailure(truncatedDetail(originalMessage))
    }

    // Requires the digits to be introduced by "status ", "status code ", or ": " — a bare
    // three-digit run would also match a port number, a path segment, or an item count
    // (see "cache returned 5000 stale entries" in the tests), so the prefix is what tells
    // an HTTP status apart from any other number that happens to appear in the message.
    private static let statusCodeRegex = try! NSRegularExpression(
        pattern: #"(?:status(?: code)?\s+|:\s+)(?<!\d)([45]\d{2})(?!\d)"#
    )

    private func httpStatusCode(in message: String) -> Int? {
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = Self.statusCodeRegex.firstMatch(in: message, range: range),
              let codeRange = Range(match.range(at: 1), in: message) else {
            return nil
        }
        return Int(message[codeRange])
    }

    private func truncatedDetail(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "RPC error" }
        guard trimmed.count > 80 else { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }
}
