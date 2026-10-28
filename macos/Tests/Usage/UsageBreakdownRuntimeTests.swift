#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct UsageBreakdownRuntimeTests {
    final class Clock {
        var now = Date()
    }

    let pane = UUID()

    func makeDefaults() -> UserDefaults {
        let name = "UsageBreakdownRuntimeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A conversation with one Opus reply (weight 40) an hour ago, reported
    /// to a fresh ledger that also holds one Haiku run (weight 40).
    func setUp(_ clock: Clock) throws -> (UsageBreakdownRuntime, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ubr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s.jsonl")
        let at = (clock.now - 3600).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        try Data((#"{"type":"assistant","timestamp":"\#(at)","requestId":"r","message":{"id":"m","#
            + #""model":"claude-opus-5-5","usage":{"input_tokens":10}}}"# + "\n").utf8).write(to: file)
        let ledger = UsageLedger(url: dir.appendingPathComponent("ledger.json"))
        ledger.reported(file.path, at: clock.now, locate: { TranscriptLocation(url: URL(fileURLWithPath: $0), agent: .claude) })
        ledger.record(["claude-haiku-5-5": TokenCounts(input: 400)], source: .observer, at: clock.now - 60)
        return (UsageBreakdownRuntime(ledger: ledger, counter: UsageCounter(), now: { clock.now }), file)
    }

    func usage(_ clock: Clock, session: Double = 42, week: Double = 17) -> ClaudeUsageRuntime {
        let usage = ClaudeUsageRuntime(defaults: makeDefaults(), now: { clock.now })
        let reset = Int(clock.now.timeIntervalSince1970) + 3600
        usage.userVarChanged(pane, name: "LOSTTY_USAGE", value:
            #"{"v":1,"five":{"pct":\#(session),"reset":\#(reset)},"week":{"pct":\#(week),"reset":\#(reset + 86400)}}"#)
        return usage
    }

    @Test func countsThenSplitsEachLimit() async throws {
        let clock = Clock()
        let (runtime, _) = try setUp(clock)
        let usage = usage(clock)
        #expect(runtime.line(.session, usage: usage) == nil)
        let task = runtime.refresh()
        #expect(runtime.isCounting)
        #expect(runtime.line(.session, usage: usage) == UsageBreakdownRuntime.counting)
        await task?.value
        #expect(!runtime.isCounting)
        #expect(runtime.line(.session, usage: usage) == "Claude Code ≈ 21 · Lostty ≈ 21")
        #expect(runtime.line(.weekly, usage: usage) == "Claude Code ≈ 8 · Lostty ≈ 9")
        #expect(runtime.line(.weeklyFable, usage: usage) == nil)
    }

    @Test func aCountIsReusedForAMinute() async throws {
        let clock = Clock()
        let (runtime, file) = try setUp(clock)
        await runtime.refresh()?.value
        // A new reply doesn't show until the minute is up.
        let at = clock.now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((#"{"type":"assistant","timestamp":"\#(at)","requestId":"r2","#
            + #""message":{"id":"m2","model":"claude-opus-5-5","usage":{"input_tokens":10}}}"# + "\n").utf8))
        try handle.close()
        #expect(runtime.refresh() == nil)
        #expect(runtime.uses?.count == 2)
        clock.now += 61
        await runtime.refresh()?.value
        #expect(runtime.uses?.count == 3)
    }

    @Test func noLimitReportMeansNoLine() async throws {
        let clock = Clock()
        let (runtime, _) = try setUp(clock)
        await runtime.refresh()?.value
        let empty = ClaudeUsageRuntime(defaults: makeDefaults(), now: { clock.now })
        #expect(runtime.line(.session, usage: empty) == nil)
        #expect(runtime.line(.weekly, usage: empty) == nil)
    }
}
#endif
