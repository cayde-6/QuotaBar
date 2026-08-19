import Foundation

/// Thread-safe accumulator for stderr output, used only to classify failures
/// (e.g. "command not found"). Never logged or shown verbatim to the user.
final class StderrCollector: @unchecked Sendable {
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
