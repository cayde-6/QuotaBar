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
}
