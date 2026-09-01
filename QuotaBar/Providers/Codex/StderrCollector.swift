import Foundation

/// Thread-safe accumulator for stderr output. Drained continuously so the pipe never fills
/// and blocks the child process; the collected text is surfaced only as free-form detail on
/// an error that has already been classified some other way, never used to pick which error
/// case gets thrown — see the callers for why.
final class StderrCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var eofReached = false

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    // Call when the readabilityHandler observes EOF (an empty `availableData` read). Just
    // flips a flag under `lock` — there is no one to wake, since callers poll
    // `hasReachedEndOfFile` instead of parking on a condition.
    func markEndOfFile() {
        lock.lock()
        eofReached = true
        lock.unlock()
    }

    // Cheap, synchronous, non-blocking check of whether EOF has been observed yet. Callers
    // that need to wait for EOF do so by polling this from an `await Task.sleep` loop rather
    // than blocking a thread on a condition variable: the main caller (`CodexQuotaProvider`)
    // is an actor, and parking one of Swift Concurrency's cooperative threads here would
    // starve the pool instead of just costing the one task that's waiting.
    var hasReachedEndOfFile: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eofReached
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        // Substitutes U+FFFD for any invalid byte instead of discarding the whole buffer —
        // one stray non-UTF-8 byte (a dotfile printing latin-1, an unlucky buffer split)
        // must not silently destroy an otherwise readable message.
        return String(decoding: data, as: UTF8.self)
    }

    // A one-line, human-readable summary of the collected stderr, suitable for appending to
    // an error message. codex writes ANSI-colored tracing output (e.g. "\u{1B}[2m...ERROR...
    // \u{1B}[0m"), which must be stripped before this ever reaches the UI. Returns nil when
    // there is nothing usable, so callers can fall back to the error's own message.
    //
    // This is the LAST non-empty stderr line, which can be noise from the user's own zsh
    // dotfiles rather than anything codex printed (e.g. `.zprofile` prints "nvm: command not
    // found", codex then dies silently, and that line is what gets shown as the reason). This
    // is accepted: it is detail text only, it never changes which QuotaError case is thrown,
    // and the provider is never hidden because of it — so no heuristic filtering is applied.
    var usableTail: String? {
        var stripped = text
        // OSC (Operating System Command), e.g. "\u{1B}]0;title\u{07}", terminated by BEL or
        // by ST ("\u{1B}\\").
        stripped = stripped.replacingOccurrences(
            of: "\u{1B}][^\u{1B}\u{07}]*(\u{07}|\u{1B}\\\\)",
            with: "",
            options: .regularExpression
        )
        // CSI (Control Sequence Introducer): ESC '[' + parameter bytes (0x30-0x3F, which
        // includes the private-parameter markers "<=>?", e.g. "\u{1B}[?25l") + intermediate
        // bytes (0x20-0x2F) + a single final byte (0x40-0x7E).
        stripped = stripped.replacingOccurrences(
            of: "\u{1B}\\[[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        // Two-character ("nF") escapes: ESC + intermediate bytes (0x20-0x2F) + a single
        // final byte (0x30-0x7E), e.g. "\u{1B}(B" selecting a G0 character set.
        stripped = stripped.replacingOccurrences(
            of: "\u{1B}[ -/]*[0-~]",
            with: "",
            options: .regularExpression
        )
        // Backstop: drop any remaining C0/C1 control scalars (keeping '\n', still needed
        // below for line splitting) in case a malformed or truncated escape slipped past the
        // rules above. Must run AFTER the escape-stripping above, not before, or it would
        // orphan escape bodies (e.g. leave "[?25l" behind after eating only the ESC).
        stripped = stripped.replacingOccurrences(
            of: "[\u{00}-\u{09}\u{0B}-\u{1F}\u{7F}-\u{9F}]",
            with: "",
            options: .regularExpression
        )
        guard let lastLine = stripped
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .last(where: { !$0.isEmpty })
        else {
            return nil
        }
        let collapsed = lastLine.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard collapsed.count > 80 else { return collapsed }
        return String(collapsed.prefix(80)) + "…"
    }
}
