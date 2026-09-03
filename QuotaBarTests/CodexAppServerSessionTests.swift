import Foundation
import Testing

@Suite("CodexAppServerSession.classifyRPCError")
struct CodexAppServerSessionClassifyTests {
    @Test("a timeout message classifies as a timeout")
    func timeoutMessage() {
        let result = CodexAppServerSession().classifyRPCError(["message": "the request timed out"])
        #expect(result == .network("timeout"))
    }

    @Test("the specific unreachable rule still wins over the new status rule")
    func unreachableStillWins() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "error sending request for url (https://chatgpt.com/backend-api/wham/usage_v2)"
        ])
        #expect(result == .network("unreachable"))
    }

    @Test("a message with no URL and no keyword falls through unchanged")
    func noMarkersFallsThrough() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "internal assertion failed in model manager"
        ])
        #expect(result == .unexpectedFailure("internal assertion failed in model manager"))
    }

    @Test("a long message with no URL and no keyword is truncated to 80 chars plus an ellipsis")
    func longMessageWithNoMarkersIsTruncated() {
        let message = String(repeating: "a", count: 90)
        let result = CodexAppServerSession().classifyRPCError(["message": message])
        guard case .unexpectedFailure(let detail) = result else {
            Issue.record("expected .unexpectedFailure, got \(result)")
            return
        }
        #expect(detail.count == 81)
        #expect(detail.hasSuffix("…"))
    }

    @Test("an absent message key falls back to a generic RPC error detail")
    func absentMessageFallsBack() {
        let result = CodexAppServerSession().classifyRPCError([:])
        #expect(result == .unexpectedFailure("RPC error"))
    }

    @Test("the exited-without-answering detail constant is non-empty")
    func exitedWithoutAnsweringDetailIsNonEmpty() {
        #expect(!CodexAppServerSession.exitedWithoutAnsweringDetail.isEmpty)
    }

    @Test("a status introduced by \"unexpected status\" classifies as that HTTP status")
    func unexpectedStatusPrefixClassifiesAsHTTPStatus() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "failed to fetch codex rate limits: GET https://chatgpt.com/backend-api/wham/usage_v2: unexpected status 500 Internal Server Error"
        ])
        #expect(result == .network("HTTP 500"))
    }

    @Test("a status introduced by a bare colon classifies as that HTTP status")
    func colonPrefixClassifiesAsHTTPStatus() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "failed to fetch codex rate limits: GET https://chatgpt.com/backend-api/wham/usage_v2: 503 Service Unavailable"
        ])
        #expect(result == .network("HTTP 503"))
    }

    @Test("a 403 status classifies as unauthorized, not a network error")
    func status403ClassifiesAsUnauthorized() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "GET https://chatgpt.com/backend-api/wham/usage_v2: 403 Forbidden"
        ])
        #expect(result == .unauthorized)
    }

    @Test("a 401 status classifies as not authenticated, matching the old \"401\" keyword")
    func status401ClassifiesAsNotAuthenticated() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "GET https://chatgpt.com/backend-api/wham/usage_v2: 401 Unauthorized"
        ])
        #expect(result == .notAuthenticated)
    }

    @Test("the status is read before the \"auth\" substring in a URL like auth.openai.com")
    func statusReadBeforeAuthSubstringInURL() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "GET https://auth.openai.com/oauth/token: unexpected status 500 Internal Server Error"
        ])
        #expect(result == .network("HTTP 500"))
    }

    @Test("codex's real \"no snapshots returned\" message has no status and falls through with its own words")
    func noSnapshotsReturnedFallsThroughWithOwnWords() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "failed to fetch codex rate limits: no snapshots returned"
        ])
        #expect(result == .unexpectedFailure("failed to fetch codex rate limits: no snapshots returned"))
    }

    @Test("codex's real \"chatgpt authentication required\" message classifies as not authenticated")
    func chatgptAuthenticationRequiredClassifiesAsNotAuthenticated() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "chatgpt authentication required to read rate limits"
        ])
        #expect(result == .notAuthenticated)
    }

    @Test("a four-digit count after a colon is not mistaken for a three-digit HTTP status")
    func fourDigitCountIsNotMistakenForStatus() {
        let result = CodexAppServerSession().classifyRPCError([
            "message": "failed to fetch codex rate limits: cache returned 5000 stale entries"
        ])
        #expect(result == .unexpectedFailure("failed to fetch codex rate limits: cache returned 5000 stale entries"))
    }
}
