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
        let message = (error["message"] as? String ?? "").lowercased()
        let authKeywords = ["auth", "login", "sign in", "unauthorized", "401"]
        if authKeywords.contains(where: { message.contains($0) }) {
            return .notAuthenticated
        }
        return .malformedResponse
    }
}
