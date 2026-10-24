#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct PaneSubagentsTests {
    private func agent(_ id: String) -> PaneSubagent {
        PaneSubagent(id: id, type: "Explore", transcript: "/h/.claude/projects/p/s/subagents/agent-\(id).jsonl")
    }

    @Test func readsASubagentStartingAndFinishing() {
        // Exact JSON `+claude-state subagent` encodes (see protocol.zig).
        let started = #"{"v":1,"state":"subagent","agent":{"id":"a1","type":"Explore","transcript":"/p/agent-a1.jsonl"}}"#
        #expect(ClaudeMessage.subagent(started) == .started(PaneSubagent(id: "a1", type: "Explore", transcript: "/p/agent-a1.jsonl")))
        let done = #"{"v":1,"state":"subagent_done","agent":{"id":"a1","type":"Explore","transcript":"/p/agent-a1.jsonl"}}"#
        #expect(ClaudeMessage.subagent(done) == .stopped(PaneSubagent(id: "a1", type: "Explore", transcript: "/p/agent-a1.jsonl")))
        #expect(ClaudeMessage.subagent(#"{"v":1,"state":"subagent","agent":{"id":"a1"}}"#) == nil)
        #expect(ClaudeMessage.subagent(#"{"v":1,"state":"busy"}"#) == nil)
    }

    @Test func newOnesGoLastAndFinishedOnesStay() {
        var list = PaneSubagents.updated([], with: .started(agent("a")))
        list = PaneSubagents.updated(list, with: .started(agent("b")))
        list = PaneSubagents.updated(list, with: .started(agent("a")))
        list = PaneSubagents.updated(list, with: .stopped(agent("a")))
        #expect(list.map(\.id) == ["a", "b"])
        #expect(list.map(\.done) == [true, false])
    }

    @Test func oneFinishedBeforeLosttyHeardItStartIsListedDone() {
        let list = PaneSubagents.updated([], with: .stopped(agent("x")))
        #expect(list.map(\.id) == ["x"])
        #expect(list.first?.done == true)
    }

    @Test func onlyTheNewestAreKept() {
        var list: [PaneSubagent] = []
        for index in 0..<(PaneSubagents.limit + 3) { list = PaneSubagents.updated(list, with: .started(agent("\(index)"))) }
        #expect(list.count == PaneSubagents.limit)
        #expect(list.first?.id == "3")
    }

    @Test func onlySubagentTranscriptsInClaudesFolderOpen() {
        let home = "/Users/me", env: [String: String] = [:]
        #expect(SubagentPane.allowed("/Users/me/.claude/projects/p/s1/subagents/agent-a1.jsonl", home: home, environment: env))
        #expect(!SubagentPane.allowed("/Users/me/.claude/projects/p/s1.jsonl", home: home, environment: env))
        #expect(!SubagentPane.allowed("/Users/me/.claude/projects/p/s1/subagents/notes.jsonl", home: home, environment: env))
        #expect(!SubagentPane.allowed("/Users/me/.claude/projects/../../../etc/subagents/agent-a.jsonl", home: home, environment: env))
        #expect(!SubagentPane.allowed("/tmp/s1/subagents/agent-a1.jsonl", home: home, environment: env))
        #expect(!SubagentPane.allowed("/Users/me/.codex/sessions/s1/subagents/agent-a1.jsonl", home: home, environment: env))
    }

    @Test func thePaneRunsTheWatcherWithEachArgumentQuoted() {
        #expect(SubagentPane.command(binary: "/Applications/Lostty.app/Contents/MacOS/lostty", transcript: "/h/it's/agent-a.jsonl")
            == #"'/Applications/Lostty.app/Contents/MacOS/lostty' +agent-watch '/h/it'\''s/agent-a.jsonl'"#)
    }
}
#endif
