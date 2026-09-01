import Foundation

/// Fetches Codex rate-limit data from the local `codex app-server` process via JSON-RPC 2.0
/// over stdin/stdout, one JSON object per line.
actor CodexQuotaProvider: QuotaProviding {
    private let timeout: TimeInterval = 25

    // codex app-server never shows system dialogs on its own, so `allowInteraction` has
    // nothing to do here — the parameter exists only to satisfy the shared
    // QuotaProviding contract that ClaudeQuotaProvider's Keychain prompt needs.
    func fetch(allowInteraction: Bool) async throws -> ProviderQuota {
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
            if chunk.isEmpty {
                // An empty read is the EOF signal, not "nothing happened this time".
                stderrCollector.markEndOfFile()
            } else {
                stderrCollector.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            // This is a failure to launch /bin/zsh itself, not evidence that `codex` is
            // missing — the shell hasn't even had a chance to try running it yet.
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw QuotaError.unexpectedFailure("failed to launch shell: \(error.localizedDescription)")
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
                    try await CodexAppServerSession().talk(stdin: stdinPipe.fileHandleForWriting, stdout: stdoutPipe.fileHandleForReading)
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
            // The stderr text is still being drained by the readabilityHandler above so the
            // pipe never fills up and blocks the child process — but it's no longer used to
            // classify the failure. Matching substrings across the whole accumulated stderr
            // turned out to be unreliable: `codex` runs through `/bin/zsh -lc`, so stderr is
            // routinely polluted by the user's own `.zshrc`/`.zshenv` (e.g. a stray "nvm:
            // command not found"), and `codex app-server` itself can write arbitrary text
            // containing the word "codex" to stderr without meaning "not installed".
            //
            // The pipe hits EOF exactly when the shell exits, so `process.isRunning` right
            // here can still read `true` even though the process is finishing up — checking
            // `terminationStatus` at that instant could miss a real 127 and silently break
            // "CLI not found" detection. Give the process a short, bounded window to actually
            // finish before reading its exit status.
            var waited = 0
            while process.isRunning, waited < 20 {
                try? await Task.sleep(for: .milliseconds(10))
                waited += 1
            }
            // zsh returns 127 for "command not found"; because `codex` is invoked via `exec`,
            // that 127 becomes the exit status of the shell process itself. On the timeout
            // path above, the process is killed with `terminate()` instead, which produces a
            // signal-based status, not 127 — so this check doesn't misfire there.
            if !process.isRunning, process.terminationStatus == 127 {
                throw QuotaError.cliNotFound
            }
            // stderr is detail only, never a classifier (see the comment above): it can only
            // enrich the message of a failure that's already been decided as unattributable,
            // never change which QuotaError case gets thrown.
            if let quotaError = error as? QuotaError,
               case .unexpectedFailure(let detail) = quotaError {
                // The readabilityHandler drains stderr on its own queue, and a process that
                // died quickly (exactly the case this exists for) can already be gone by the
                // time we get here, with its last chunk not yet delivered. Poll for the drain
                // to actually reach EOF, bounded, so the detail isn't lost to a race — an
                // `await Task.sleep` loop rather than a blocking wait, since this runs inside
                // an actor and blocking a cooperative thread here would stall other work on
                // the pool, not just this call. Only done on this path — it must not slow
                // down the successful path or the 127 check above.
                var stderrWaited = 0
                while !stderrCollector.hasReachedEndOfFile, stderrWaited < 30 {
                    try? await Task.sleep(for: .milliseconds(10))
                    stderrWaited += 1
                }
                if let tail = stderrCollector.usableTail {
                    throw QuotaError.unexpectedFailure("\(detail): \(tail)")
                }
            }
            throw error
        }
    }
}
