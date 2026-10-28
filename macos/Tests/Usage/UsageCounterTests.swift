#if os(macOS)
import Darwin
import Foundation
import Testing
@testable import Lostty

struct UsageCounterTests {
    let now = Date()
    var since: Date { now - 7 * 24 * 3600 }

    func stamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    /// One line of a reply, the way Claude Code writes them: a reply with
    /// several content items is several lines with the same id and tokens.
    func reply(_ id: String, at: Date? = nil, model: String = "claude-haiku-5-5", input: Int = 10,
               content: String = "text") -> String {
        let at = stamp(at ?? now - 3600)
        return #"{"type":"assistant","timestamp":"\#(at)","requestId":"req-\#(id)","isSidechain":false,"#
            + #""message":{"id":"msg-\#(id)","model":"\#(model)","content":[{"type":"\#(content)"}],"#
            + #""usage":{"input_tokens":\#(input),"output_tokens":0,"cache_creation_input_tokens":0,"#
            + #""cache_read_input_tokens":0}}}"#
    }

    let prompt = #"{"type":"user","timestamp":"2026-10-14T10:00:00.000Z","message":{"role":"user","content":"hi"}}"#

    func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func write(_ lines: [String], to url: URL, newline: Bool = true) throws {
        try Data((lines.joined(separator: "\n") + (newline ? "\n" : "")).utf8).write(to: url)
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    @Test func aReplyOnSeveralLinesCountsOnce() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([prompt, reply("a", content: "thinking"), reply("a", content: "text"), reply("a", content: "tool_use"),
                   reply("b", input: 20)], to: file)
        let uses = await UsageCounter().count([file], since: since)
        #expect(uses.count == 2)
        #expect(uses.map(\.weight).sorted() == [1, 2])
        #expect(uses.allSatisfy { $0.part == .claudeCode })
    }

    @Test func repliesBeforeTheWindowDontCount() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([reply("old", at: since - 60), reply("new")], to: file)
        let uses = await UsageCounter().count([file], since: since)
        #expect(uses.count == 1)
    }

    @Test func timestampsWithOrWithoutFractionsCount() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        let plain = (now - 60).formatted(Date.ISO8601FormatStyle())
        let withoutFraction = reply("a").replacingOccurrences(of: stamp(now - 3600), with: plain)
        try write([withoutFraction, reply("b")], to: file)
        #expect(await UsageCounter().count([file], since: since).count == 2)
        #expect(UsageCounter.date("2026-10-12T05:45:50.990Z") != nil)
        #expect(UsageCounter.date("2026-10-12T05:45:50Z") != nil)
        #expect(UsageCounter.date("yesterday") == nil)
    }

    @Test func subagentsCountWithTheirConversation() async throws {
        let dir = try folder()
        let file = dir.appendingPathComponent("s.jsonl")
        try write([reply("a")], to: file)
        let subagents = dir.appendingPathComponent("s/subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try write([reply("sub", model: "claude-sonnet-5-5")], to: subagents.appendingPathComponent("agent-1.jsonl"))
        try write(["{}"], to: subagents.appendingPathComponent("agent-1.meta.json"))
        #expect(UsageCounter.withSubagents(file).map(\.lastPathComponent) == ["s.jsonl", "agent-1.jsonl"])
        let uses = await UsageCounter().count([file], since: since)
        #expect(uses.map(\.weight).sorted() == [1, 20])
    }

    @Test func aHalfWrittenLineWaitsAndNothingCountsTwice() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([reply("a"), reply("b")], to: file, newline: false)
        let counter = UsageCounter()
        #expect(await counter.count([file], since: since).count == 1)
        try append("\n" + reply("c") + "\n", to: file)
        #expect(await counter.count([file], since: since).count == 3)
        #expect(await counter.count([file], since: since).count == 3)
    }

    @Test func aSmallChunkSizeCountsTheSame() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write((0..<40).map { reply("r\($0)") } + [prompt], to: file)
        // Chunks far shorter than a line: every line spans several reads.
        #expect(await UsageCounter(chunk: 37).count([file], since: since).count == 40)
    }

    @Test func aFileThatShrankStartsOver() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([reply("a"), reply("b"), reply("c")], to: file)
        let counter = UsageCounter()
        #expect(await counter.count([file], since: since).count == 3)
        try write([reply("d", input: 40)], to: file)
        let uses = await counter.count([file], since: since)
        #expect(uses.map(\.weight) == [4])
    }

    @Test func aFileUntouchedThisWeekIsSkipped() async throws {
        let file = try folder().appendingPathComponent("s.jsonl")
        try write([reply("a")], to: file)
        try FileManager.default.setAttributes([.modificationDate: since - 3600], ofItemAtPath: file.path)
        #expect(await UsageCounter().count([file], since: since).isEmpty)
    }

    @Test func aMissingFileOrAFifoIsSkipped() async throws {
        let dir = try folder()
        let fifo = dir.appendingPathComponent("pipe.jsonl")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let missing = dir.appendingPathComponent("missing.jsonl")
        #expect(await UsageCounter().count([fifo, missing], since: since).isEmpty)
    }

    @Test func losttysRunsWeighEveryModelTheyUsed() {
        let runs = [
            LosttyRun(at: now - 60, source: .observer,
                      tokens: ["claude-haiku-5-5": TokenCounts(input: 10), "claude-sonnet-5-5": TokenCounts(input: 1)]),
            LosttyRun(at: since - 60, source: .branchSummary, tokens: ["claude-haiku-5-5": TokenCounts(input: 99)]),
        ]
        let uses = UsageCounter.uses(of: runs, since: since)
        #expect(uses == [WeightedUse(at: now - 60, part: .lostty, weight: 3)])
    }
}
#endif
