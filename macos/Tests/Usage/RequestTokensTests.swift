#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct RequestTokensTests {
    let start = Date() - 600

    /// One line of a reply: 1 input, 8 cache writes, 100 cache reads and
    /// `output` output tokens, so the sum names which replies counted.
    func reply(
        _ id: String, at: Date? = nil, output: Int = 1000, content: String = "text", model: String = "claude-opus-5-5"
    ) -> String {
        let at = (at ?? start + 60).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        return #"{"type":"assistant","timestamp":"\#(at)","requestId":"req-\#(id)","#
            + #""message":{"id":"msg-\#(id)","model":"\#(model)","content":[{"type":"\#(content)"}],"#
            + #""usage":{"input_tokens":1,"output_tokens":\#(output),"cache_creation_input_tokens":8,"#
            + #""cache_read_input_tokens":100}}}"#
    }

    /// An Opus 5.5 reply's weight: 1 + 8 × 2 + 100 × 0.05 + 5 per output token.
    func weight(_ output: Int = 1000) -> Int { 22 + 5 * output }

    /// Claude Code's record that the request's Stop hooks ran.
    var stop: String {
        let at = (start + 120).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        return #"{"type":"system","subtype":"stop_hook_summary","timestamp":"\#(at)"}"#
    }

    func counter(chunk: Int = 8 << 20, tail: UInt64 = 32 << 20) -> RequestTokens {
        RequestTokens(chunk: chunk, tail: tail, settle: .milliseconds(20), tries: 50)
    }

    let prompt = #"{"type":"user","timestamp":"2026-10-14T10:00:00.000Z","message":{"role":"user","content":"hi"}}"#

    func conversation() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("request-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("s.jsonl")
    }

    func write(_ lines: [String], to url: URL) throws {
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    func append(_ lines: [String], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
        try handle.close()
    }

    @Test func sumsTheRequestsRepliesAndItsSubagentsOnceEach() async throws {
        let file = try conversation()
        try write([reply("old", at: start - 60, output: 9000), prompt,
                   reply("a", content: "thinking"), reply("a", content: "tool_use"), reply("b", output: 2000), stop], to: file)
        let subagents = file.deletingPathExtension().appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try write([reply("sub", output: 4000)], to: subagents.appendingPathComponent("agent-1.jsonl"))
        let total = await counter().total(file, since: start)
        #expect(total == weight() + weight(2000) + weight(4000))
    }

    @Test func otherModelsWeighByTheirPriceNextToOpus() async throws {
        let file = try conversation()
        try write([reply("h", output: 999, model: "claude-sonnet-5-5"), stop], to: file)
        // Sonnet 5.5 costs half of Opus 5.5, and reads its cache at 0.1: (1 + 16 + 10 + 5 × 999) / 2.
        #expect(await counter().total(file, since: start) == 2511)
    }

    @Test func repliesWrittenAfterTheStopHookStartedStillCount() async throws {
        let file = try conversation()
        try write([prompt], to: file)
        let counter = self.counter()
        let total = Task { await counter.total(file, since: start) }
        try await Task.sleep(for: .milliseconds(100))
        try append([reply("a", output: 2000), stop], to: file)
        #expect(await total.value == weight(2000))
    }

    @Test func withoutAStopRecordItCountsWhatIsThereAfterAFewTries() async throws {
        let file = try conversation()
        try write([reply("a")], to: file)
        #expect(await RequestTokens(settle: .milliseconds(1), tries: 3).total(file, since: start) == weight())
    }

    @Test func theNextRequestCountsOnlyWhatWasAdded() async throws {
        let file = try conversation()
        try write([reply("a"), stop], to: file)
        let counter = RequestTokens(settle: .milliseconds(1), tries: 3)
        #expect(await counter.total(file, since: start) == weight())
        try append([prompt, reply("b", output: 2000), stop], to: file)
        #expect(await counter.total(file, since: start) == weight(2000))
        #expect(await counter.total(file, since: start) == 0)
    }

    @Test func aLongFileIsReadFromNearItsEndOnWholeLines() async throws {
        let file = try conversation()
        let last = reply("c", output: 3000)
        let ending = last + "\n" + stop
        try write([reply("a"), reply("b", output: 2000), ending], to: file)
        // Reaches back past the last reply into the middle of the one before.
        #expect(await counter(tail: UInt64(ending.utf8.count + 20)).total(file, since: start) == weight(3000))
        // Exactly the last reply and what follows it: that reply still counts.
        #expect(await counter(tail: UInt64(ending.utf8.count + 1)).total(file, since: start) == weight(3000))
    }

    @Test func aFileThatShrankStartsOver() async throws {
        let file = try conversation()
        try write([reply("a"), reply("b"), reply("c"), stop], to: file)
        let counter = self.counter()
        #expect(await counter.total(file, since: start) == 3 * weight())
        try write([reply("d", output: 4000), stop], to: file)
        #expect(await counter.total(file, since: start) == weight(4000))
    }

    @Test func aSmallChunkSizeCountsTheSame() async throws {
        let file = try conversation()
        try write((0..<20).map { reply("r\($0)") } + [prompt, stop], to: file)
        #expect(await counter(chunk: 37).total(file, since: start) == 20 * weight())
    }
}
#endif
