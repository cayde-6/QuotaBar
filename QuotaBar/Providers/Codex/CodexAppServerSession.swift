import Foundation

/// One JSON-RPC 2.0 conversation with a codex app-server process over stdin/stdout,
/// newline-delimited JSON per message: initialize → initialized → account/rateLimits/read.
struct CodexAppServerSession {
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

        let authKeywords = ["auth", "login", "sign in", "unauthorized", "401"]
        if authKeywords.contains(where: { message.contains($0) }) {
            return .notAuthenticated
        }

        // The result parsed fine as valid JSON-RPC, so claiming the response format
        // changed (.malformedResponse) would be wrong; .unexpectedFailure exists for
        // exactly this — a failure we can't attribute to a known category — and keeps
        // codex's own message visible instead of hiding it behind a generic label.
        return .unexpectedFailure(truncatedDetail(originalMessage))
    }

    private func truncatedDetail(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "RPC error" }
        guard trimmed.count > 80 else { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }
}
