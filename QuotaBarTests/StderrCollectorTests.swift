import Foundation
import Testing

/// Fails if any C0 control scalar (below 0x20, `\n` excepted since lines are already split
/// on it) or any C1 control scalar (0x7F...0x9F) survived `usableTail`'s stripping.
private func assertNoControlScalars(in string: String, sourceLocation: SourceLocation = #_sourceLocation) {
    for scalar in string.unicodeScalars {
        let value = scalar.value
        #expect(value >= 0x20 && !(0x7F...0x9F).contains(value), "control scalar \(String(format: "0x%02X", value)) survived", sourceLocation: sourceLocation)
    }
}

private func makeCollector(_ chunks: Data...) -> StderrCollector {
    let collector = StderrCollector()
    for chunk in chunks {
        collector.append(chunk)
    }
    return collector
}

private func makeCollector(_ string: String) -> StderrCollector {
    makeCollector(string.data(using: .utf8)!)
}

@Suite("StderrCollector.usableTail")
struct StderrCollectorUsableTailTests {
    @Test("CSI with private parameter bytes is stripped")
    func csiPrivateParameterBytes() {
        let collector = makeCollector("loading\u{1B}[?25l done")
        let tail = collector.usableTail
        #expect(tail == "loading done")
        assertNoControlScalars(in: tail ?? "")
    }

    @Test("OSC terminated by BEL is stripped")
    func oscTerminatedByBEL() {
        let collector = makeCollector("start \u{1B}]0;title\u{07} end")
        let tail = collector.usableTail
        #expect(tail == "start end")
        assertNoControlScalars(in: tail ?? "")
    }

    @Test("OSC terminated by ST is stripped")
    func oscTerminatedByST() {
        let collector = makeCollector("alpha \u{1B}]2;name\u{1B}\\ beta")
        let tail = collector.usableTail
        #expect(tail == "alpha beta")
        assertNoControlScalars(in: tail ?? "")
    }

    @Test("two-character nF escape is stripped")
    func twoCharacterNFEscape() {
        let collector = makeCollector("prefix \u{1B}(B suffix")
        let tail = collector.usableTail
        #expect(tail == "prefix suffix")
        assertNoControlScalars(in: tail ?? "")
    }

    @Test("an invalid UTF-8 byte still yields readable text")
    func invalidUTF8ByteYieldsReadableText() {
        let collector = makeCollector()
        collector.append("abc".data(using: .utf8)!)
        collector.append(Data([0xFF]))
        collector.append(" def".data(using: .utf8)!)
        let tail = collector.usableTail
        #expect(tail != nil)
        #expect(tail?.contains("abc") == true)
        #expect(tail?.contains("def") == true)
    }

    @Test("a whitespace-only final line falls back to the previous real line")
    func whitespaceOnlyFinalLineFallsBack() {
        let collector = makeCollector("real line\n   \n\t  \n")
        #expect(collector.usableTail == "real line")
    }

    @Test("a 200-character line is truncated to 81 characters ending in the ellipsis")
    func longLineIsTruncated() {
        let collector = makeCollector(String(repeating: "a", count: 200))
        let tail = collector.usableTail
        #expect(tail?.count == 81)
        #expect(tail?.hasSuffix("…") == true)
        #expect(tail?.hasPrefix(String(repeating: "a", count: 80)) == true)
    }

    @Test("empty collector returns nil")
    func emptyCollectorReturnsNil() {
        let collector = StderrCollector()
        #expect(collector.usableTail == nil)
    }

    @Test("a collector holding only whitespace returns nil")
    func whitespaceOnlyCollectorReturnsNil() {
        let collector = makeCollector("   \n\t\n  ")
        #expect(collector.usableTail == nil)
    }
}

@Suite("StderrCollector.markEndOfFile")
struct StderrCollectorEndOfFileTests {
    @Test("hasReachedEndOfFile flips from false to true")
    func markEndOfFileFlipsFlag() {
        let collector = StderrCollector()
        #expect(collector.hasReachedEndOfFile == false)
        collector.markEndOfFile()
        #expect(collector.hasReachedEndOfFile == true)
    }
}
