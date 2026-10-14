#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ConversationReaderTests {
    static let claude = [
        #"{"type":"user","message":{"role":"user","content":"Fix the login bug"}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hmm"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Looking at it."},{"type":"tool_use","id":"t1","name":"Read","input":{}}]}}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"SECRET FILE"}]}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Fixed it."}]}}"#,
        #"{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>x</local-command-caveat>"}}"#,
        #"{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"}}"#,
        #"{"type":"user","message":{"role":"user","content":"<bash-input>ls</bash-input>"}}"#,
        #"{"type":"user","isSidechain":true,"message":{"role":"user","content":"subagent prompt"}}"#,
        #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"subagent reply"}]}}"#,
        #"{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued"}}"#,
        #"{"type":"attachment","attachment":{}}"#,
        #"{"type":"user","message":{"role":"user","content":"Thanks <system-reminder>noise</system-reminder>now ship it"}}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Look at this"},{"type":"image","source":{}}]}}"#,
    ].joined(separator: "\n") + "\n"

    static let codex = [
        #"{"type":"session_meta","payload":{"id":"x"}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"sandbox rules"}]}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>\n  <cwd>/tmp</cwd>\n</environment_context>"}]}}"#,
        ##"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions for /tmp\n\n<INSTRUCTIONS>x</INSTRUCTIONS>"}]}}"##,
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"count to 3"}]}}"#,
        #"{"type":"response_item","payload":{"type":"reasoning","summary":[]}}"#,
        #"{"type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{}"}}"#,
        #"{"type":"response_item","payload":{"type":"function_call_output","output":"SECRET"}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"1"}]}}"#,
        #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"2, 3"}]}}"#,
        #"{"type":"event_msg","payload":{"type":"agent_message","message":"2, 3"}}"#,
    ].joined(separator: "\n") + "\n"

    @Test func claudeKeepsOnlyPromptsAndReplies() {
        let parsed = ConversationReader.parse(Data(Self.claude.utf8), agent: .claude)
        #expect(parsed.entries == [
            ConversationEntry(speaker: .you, text: "Fix the login bug"),
            ConversationEntry(speaker: .agent, text: "Looking at it.\n\nFixed it."),
            ConversationEntry(speaker: .you, text: "Thanks now ship it"),
            ConversationEntry(speaker: .you, text: "Look at this"),
        ])
        #expect(parsed.consumed == Self.claude.utf8.count)
    }

    @Test func codexKeepsOnlyPromptsAndReplies() {
        let parsed = ConversationReader.parse(Data(Self.codex.utf8), agent: .codex)
        #expect(parsed.entries == [
            ConversationEntry(speaker: .you, text: "count to 3"),
            ConversationEntry(speaker: .agent, text: "1\n\n2, 3"),
        ])
    }

    @Test func aHalfWrittenLastLineWaits() {
        let whole = #"{"type":"user","message":{"role":"user","content":"hi"}}"# + "\n"
        let data = Data((whole + #"{"type":"assistant","message":{"ro"#).utf8)
        let parsed = ConversationReader.parse(data, agent: .claude)
        #expect(parsed.entries == [ConversationEntry(speaker: .you, text: "hi")])
        #expect(parsed.consumed == whole.utf8.count)
    }

    @Test func garbageLinesAreSkipped() {
        let data = Data("not json\n[1]\n\n".utf8)
        #expect(ConversationReader.parse(data, agent: .claude).entries.isEmpty)
    }

    func file(_ text: String) throws -> TranscriptLocation {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("conv-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: url)
        return TranscriptLocation(url: url, agent: .claude)
    }

    @Test func readingFromAnOffsetReturnsOnlyWhatsNew() throws {
        let first = #"{"type":"user","message":{"role":"user","content":"one"}}"# + "\n"
        let location = try file(first)
        let chunk = try #require(ConversationReader.read(location, from: 0))
        #expect(chunk.entries == [ConversationEntry(speaker: .you, text: "one")])
        #expect(chunk.offset == UInt64(first.utf8.count))
        #expect(!chunk.restarted)

        let handle = try FileHandle(forWritingTo: location.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((#"{"type":"user","message":{"role":"user","content":"two"}}"# + "\n").utf8))
        try handle.close()
        let next = try #require(ConversationReader.read(location, from: chunk.offset))
        #expect(next.entries == [ConversationEntry(speaker: .you, text: "two")])
    }

    @Test func aShorterFileIsReadFromTheStart() throws {
        let location = try file(#"{"type":"user","message":{"role":"user","content":"new"}}"# + "\n")
        let chunk = try #require(ConversationReader.read(location, from: 10_000))
        #expect(chunk.restarted)
        #expect(chunk.entries == [ConversationEntry(speaker: .you, text: "new")])
    }

    @Test func aFifoOrFolderIsNotRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fifo = dir.appendingPathComponent("pipe.jsonl")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(ConversationReader.read(TranscriptLocation(url: fifo, agent: .claude), from: 0) == nil)
        let folder = dir.appendingPathComponent("folder.jsonl")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(ConversationReader.read(TranscriptLocation(url: folder, agent: .claude), from: 0) == nil)
    }

    @Test func theTailStartsAtTheLatestPrompt() {
        let you = ConversationEntry(speaker: .you, text: "go")
        let a = ConversationEntry(speaker: .agent, text: "part one")
        let b = ConversationEntry(speaker: .agent, text: "part two")
        // A permission prompt ended the first run mid-reply; the rest came later.
        let first = ConversationReader.tail([], adding: [ConversationEntry(speaker: .you, text: "old"), you, a])
        #expect(first == [you, a])
        let second = ConversationReader.tail(first, adding: [b])
        #expect(second == [you, ConversationEntry(speaker: .agent, text: "part one\n\npart two")])
        #expect(ConversationReader.lastReply(second) == "part one\n\npart two")
        #expect(ConversationReader.tail(second, adding: [ConversationEntry(speaker: .you, text: "next")])
            == [ConversationEntry(speaker: .you, text: "next")])
        #expect(ConversationReader.lastReply([ConversationEntry(speaker: .you, text: "next")]) == "")
    }
}
#endif
