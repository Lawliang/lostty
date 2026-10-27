#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct RequestTokensTests {
    let start = Date() - 600

    /// One line of a reply: 1 input, 10 cache writes, 100 cache reads and
    /// `output` output tokens, so the sum names which replies counted.
    func reply(_ id: String, at: Date? = nil, output: Int = 1000, content: String = "text") -> String {
        let at = (at ?? start + 60).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        return #"{"type":"assistant","timestamp":"\#(at)","requestId":"req-\#(id)","#
            + #""message":{"id":"msg-\#(id)","model":"claude-opus-5-5","content":[{"type":"\#(content)"}],"#
            + #""usage":{"input_tokens":1,"output_tokens":\#(output),"cache_creation_input_tokens":10,"#
            + #""cache_read_input_tokens":100}}}"#
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
                   reply("a", content: "thinking"), reply("a", content: "tool_use"), reply("b", output: 2000)], to: file)
        let subagents = file.deletingPathExtension().appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        try write([reply("sub", output: 4000)], to: subagents.appendingPathComponent("agent-1.jsonl"))
        let total = await RequestTokens().total(file, since: start)
        #expect(total == 1111 + 2111 + 4111)
    }

    @Test func theNextRequestCountsOnlyWhatWasAdded() async throws {
        let file = try conversation()
        try write([reply("a")], to: file)
        let counter = RequestTokens()
        #expect(await counter.total(file, since: start) == 1111)
        try append([prompt, reply("b", output: 2000)], to: file)
        #expect(await counter.total(file, since: start) == 2111)
        #expect(await counter.total(file, since: start) == 0)
    }

    @Test func aLongFileIsReadFromNearItsEndOnWholeLines() async throws {
        let file = try conversation()
        let last = reply("c", output: 3000)
        try write([reply("a"), reply("b", output: 2000), last], to: file)
        // Reaches back past the last line into the middle of the one before.
        let counter = RequestTokens(tail: UInt64(last.utf8.count + 20))
        #expect(await counter.total(file, since: start) == 3111)
        // Exactly the last line and its newline: that line still counts.
        #expect(await RequestTokens(tail: UInt64(last.utf8.count + 1)).total(file, since: start) == 3111)
    }

    @Test func aFileThatShrankStartsOver() async throws {
        let file = try conversation()
        try write([reply("a"), reply("b"), reply("c")], to: file)
        let counter = RequestTokens()
        #expect(await counter.total(file, since: start) == 3 * 1111)
        try write([reply("d", output: 4000)], to: file)
        #expect(await counter.total(file, since: start) == 4111)
    }

    @Test func aSmallChunkSizeCountsTheSame() async throws {
        let file = try conversation()
        try write((0..<20).map { reply("r\($0)") } + [prompt], to: file)
        #expect(await RequestTokens(chunk: 37).total(file, since: start) == 20 * 1111)
    }
}
#endif
