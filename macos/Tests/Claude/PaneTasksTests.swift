#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct PaneTasksTests {
    private func agent(_ id: String) -> PaneTask {
        PaneTask(id: id, kind: .subagent, title: "Explore", path: "/h/.claude/projects/p/s/subagents/agent-\(id).jsonl")
    }

    @Test func readsSubagentsAndShellsStartingAndFinishing() {
        // Exact JSON `+claude-state` encodes (see protocol.zig).
        let started = #"{"v":1,"state":"subagent","agent":{"id":"a1","type":"Explore","transcript":"/p/agent-a1.jsonl"}}"#
        let a1 = PaneTask(id: "a1", kind: .subagent, title: "Explore", path: "/p/agent-a1.jsonl")
        #expect(ClaudeMessage.task(started) == .started(a1))
        let done = #"{"v":1,"state":"subagent_done","agent":{"id":"a1","type":"Explore","transcript":"/p/agent-a1.jsonl"}}"#
        #expect(ClaudeMessage.task(done) == .finished("a1"))
        let shell = #"{"v":1,"state":"shell","shell":{"id":"b1","description":"Dev server","output":"/t/tasks/b1.output"}}"#
        #expect(ClaudeMessage.task(shell) == .started(PaneTask(id: "b1", kind: .shell, title: "Dev server", path: "/t/tasks/b1.output")))
        #expect(ClaudeMessage.task(#"{"v":1,"state":"shell","shell":{"id":"b2"}}"#)
            == .started(PaneTask(id: "b2", kind: .shell, title: "Shell", path: nil)))
        #expect(ClaudeMessage.task(#"{"v":1,"state":"shell_done","shell":{"id":"b1"}}"#) == .finished("b1"))
        #expect(ClaudeMessage.task(#"{"v":1,"state":"subagent","agent":{"id":"a1"}}"#) == nil)
        #expect(ClaudeMessage.task(#"{"v":1,"state":"busy"}"#) == nil)
    }

    @Test func newOnesGoLastAndFinishedOnesGo() {
        var list = PaneTasks.updated([], with: .started(agent("a")))
        list = PaneTasks.updated(list, with: .started(agent("b")))
        list = PaneTasks.updated(list, with: .started(agent("c")))
        list = PaneTasks.updated(list, with: .started(agent("a")))
        #expect(list.map(\.id) == ["a", "b", "c"])
        list = PaneTasks.updated(list, with: .finished("b"))
        list = PaneTasks.updated(list, with: .finished("unknown"))
        #expect(list.map(\.id) == ["a", "c"])
    }

    @Test func onlyTheNewestAreKept() {
        var list: [PaneTask] = []
        for index in 0..<(PaneTasks.limit + 3) { list = PaneTasks.updated(list, with: .started(agent("\(index)"))) }
        #expect(list.count == PaneTasks.limit)
        #expect(list.first?.id == "3")
    }

    @MainActor @Test func thePanesListGoesWithItsLastTask() {
        let tasks = PaneTasks()
        let pane = UUID()
        tasks.apply(.started(agent("a")), to: pane)
        tasks.apply(.started(agent("b")), to: pane)
        tasks.apply(.finished("a"), to: pane)
        #expect(tasks.lists[pane]?.map(\.id) == ["b"])
        tasks.apply(.finished("b"), to: pane)
        #expect(tasks.lists[pane] == nil)
    }

    @Test func onlyClaudesOwnFilesAreRead() {
        let home = "/Users/me", env: [String: String] = [:]
        func subagent(_ path: String) -> String? {
            PaneTask(id: "a1", kind: .subagent, title: "Explore", path: path).readablePath(home: home, environment: env, user: 501)
        }
        func shell(_ path: String, id: String = "b1") -> String? {
            PaneTask(id: id, kind: .shell, title: "Shell", path: path).readablePath(home: home, environment: env, user: 501)
        }
        #expect(subagent("/Users/me/.claude/projects/p/s1/subagents/agent-a1.jsonl") != nil)
        #expect(subagent("/Users/me/.claude/projects/p/s1.jsonl") == nil)
        #expect(subagent("/Users/me/.claude/projects/p/s1/subagents/notes.jsonl") == nil)
        #expect(subagent("/Users/me/.claude/projects/../../../etc/subagents/agent-a.jsonl") == nil)
        #expect(subagent("/Users/me/.codex/sessions/s1/subagents/agent-a1.jsonl") == nil)
        #expect(shell("/private/tmp/claude-501/-p/s1/tasks/b1.output") != nil)
        #expect(shell("/private/tmp/claude-501/-p/s1/tasks/b2.output") == nil)
        #expect(shell("/private/tmp/claude-502/-p/s1/tasks/b1.output") == nil)
        #expect(shell("/private/tmp/claude-501/../../etc/tasks/b1.output") == nil)
        #expect(shell("/Users/me/tasks/b1.output") == nil)
    }

    @Test func aSubagentsTranscriptReadsAsItsSteps() {
        func line(_ object: [String: Any]) -> Data {
            (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        }
        let lines = [
            line(["parentUuid": NSNull(), "type": "user", "message": ["content": "Find where zones load.\nBe brief."]]),
            line(["parentUuid": "1", "type": "assistant", "message": ["content": [
                ["type": "tool_use", "name": "Grep", "input": ["pattern": "zone"]],
                ["type": "tool_use", "name": "Read", "input": ["file_path": "/r/Canvas.swift"]],
            ]]]),
            line(["parentUuid": "2", "type": "user", "message": ["content": [
                ["type": "tool_result", "is_error": true, "content": "No such file\nmore"],
            ]]]),
            line(["parentUuid": "3", "type": "assistant", "message": ["stop_reason": "end_turn", "content": [
                ["type": "text", "text": "Zones load in CanvasZoneStore."],
            ]]]),
        ]
        let feed = TaskFeed.subagent(lines)
        #expect(feed.map(\.0) == [
            "Find where zones load.", "Be brief.", "▸ Searching for \"zone\"", "▸ Reading Canvas.swift",
            "✗ No such file", "Zones load in CanvasZoneStore.", "✓ Done",
        ])
        #expect(feed.map(\.1) == [.brief, .brief, .action, .action, .failed, .words, .done])
    }

    @Test func aShellsOutputLosesItsEscapesAndKeepsWhatAProgressBarEndedOn() {
        let output = Data("\u{1B}[32mready\u{1B}[0m on :5173\n10%\r50%\r100%\n\u{1B}]0;title\u{07}GET / 200\n\n".utf8)
        #expect(TaskFeed.shell(output) == ["ready on :5173", "100%", "GET / 200"])
    }

    @Test func toolCallsAreWordedAsTheWatcherWordsThem() {
        #expect(TaskFeed.action("Edit", ["file_path": "/a/b/Foo.swift"]) == "Editing Foo.swift")
        #expect(TaskFeed.action("Bash", ["command": "rm -rf x", "description": "Clean up"]) == "Clean up")
        #expect(TaskFeed.action("WebFetch", ["url": "https://docs.example.com/a"]) == "Reading docs.example.com")
        #expect(TaskFeed.action("mcp__xcode__build_sim", [:]) == "build_sim")
        #expect(TaskFeed.action("Mystery", [:]) == "Mystery")
    }
}
#endif
