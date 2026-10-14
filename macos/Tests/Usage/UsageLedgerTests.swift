#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct UsageLedgerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 3600

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(UUID().uuidString)/usage-ledger.json")
    }

    /// Every path passes, as Claude's.
    func claude(_ path: String) -> TranscriptLocation? {
        TranscriptLocation(url: URL(fileURLWithPath: path), agent: .claude)
    }

    @Test func keepsOnlyClaudeConversations() {
        let ledger = UsageLedger(url: tempURL())
        ledger.reported("/c/a.jsonl", at: now, locate: claude)
        ledger.reported("/x/rollout-1.jsonl", at: now,
                        locate: { TranscriptLocation(url: URL(fileURLWithPath: $0), agent: .codex) })
        ledger.reported("/etc/passwd", at: now, locate: { _ in nil })
        // The real allow-list turns this away too.
        ledger.reported("/etc/passwd", at: now)
        #expect(ledger.conversations(now: now).map(\.path) == ["/c/a.jsonl"])
    }

    @Test func keepsTheResolvedPathOnce() {
        let ledger = UsageLedger(url: tempURL())
        let resolve: (String) -> TranscriptLocation? = { _ in
            TranscriptLocation(url: URL(fileURLWithPath: "/real/a.jsonl"), agent: .claude)
        }
        ledger.reported("/link/a.jsonl", at: now, locate: resolve)
        ledger.reported("/real/a.jsonl", at: now + 60, locate: resolve)
        #expect(ledger.conversations(now: now + 60).map(\.path) == ["/real/a.jsonl"])
    }

    @Test func recordsRunsAndSkipsEmptyOnes() {
        let ledger = UsageLedger(url: tempURL())
        ledger.record(["claude-haiku-5-5": TokenCounts(input: 5, output: 1)], source: .observer, at: now)
        ledger.record([:], source: .branchSummary, at: now)
        #expect(ledger.runs(now: now) == [
            LosttyRun(at: now, source: .observer, tokens: ["claude-haiku-5-5": TokenCounts(input: 5, output: 1)]),
        ])
    }

    @Test func dropsWhatsOlderThanEightDays() {
        let ledger = UsageLedger(url: tempURL())
        ledger.reported("/c/old.jsonl", at: now - 9 * day, locate: claude)
        ledger.record(["m": TokenCounts(input: 1)], source: .observer, at: now - 9 * day)
        ledger.reported("/c/new.jsonl", at: now - day, locate: claude)
        ledger.record(["m": TokenCounts(input: 2)], source: .branchSummary, at: now - day)
        #expect(ledger.conversations(now: now).map(\.path) == ["/c/new.jsonl"])
        #expect(ledger.runs(now: now).map(\.source) == [.branchSummary])
    }

    @Test func savesAndLoads() {
        let url = tempURL()
        let first = UsageLedger(url: url)
        first.reported("/c/a.jsonl", at: now, locate: claude)
        first.record(["m": TokenCounts(output: 3)], source: .branchSummary, at: now)
        let second = UsageLedger(url: url)
        #expect(second.conversations(now: now).map(\.path) == ["/c/a.jsonl"])
        #expect(second.runs(now: now) == first.runs(now: now))
    }

    @Test func anUnreadableFileReadsAsEmpty() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: url)
        let ledger = UsageLedger(url: url)
        #expect(ledger.conversations(now: now).isEmpty && ledger.runs(now: now).isEmpty)
        ledger.record(["m": TokenCounts(input: 1)], source: .observer, at: now)
        #expect(UsageLedger(url: url).runs(now: now).count == 1)
    }

    @Test func recordsFromManyThreadsAtOnce() {
        let ledger = UsageLedger(url: tempURL())
        let at = now
        DispatchQueue.concurrentPerform(iterations: 50) { i in
            ledger.record(["m": TokenCounts(input: i + 1)], source: i % 2 == 0 ? .observer : .branchSummary, at: at)
        }
        #expect(ledger.runs(now: now).count == 50)
    }
}
#endif
