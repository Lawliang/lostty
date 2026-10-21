#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct PaneConversationTests {
    let id = "0b6e3a52-7c1d-4e7f-9a51-2f3c4d5e6f70"

    @Test func claudesConversationFileNamesItsID() {
        let conversation = PaneConversation.from(transcript: "/Users/me/.claude/projects/-Users-me-app/\(id).jsonl")
        #expect(conversation == PaneConversation(agent: "claude", id: id))
        #expect(conversation?.resumeCommand == "claude --resume \(id)")
    }

    @Test func codexsRolloutFileEndsWithItsID() {
        let path = "/Users/me/.codex/sessions/2026/10/21/rollout-2026-10-21T14-02-11-\(id).jsonl"
        let conversation = PaneConversation.from(transcript: path)
        #expect(conversation == PaneConversation(agent: "codex", id: id))
        #expect(conversation?.resumeCommand == "codex resume \(id)")
    }

    @Test func anythingElseIsNoConversation() {
        #expect(PaneConversation.from(transcript: "/tmp/\(id).jsonl") == nil)
        #expect(PaneConversation.from(transcript: "/Users/me/.claude/projects/x/notes.jsonl") == nil)
        #expect(PaneConversation.from(transcript: "/Users/me/.claude/projects/x/\(id).txt") == nil)
    }

    @Test func onlyAUUIDIsEverTypedIntoTheShell() {
        // A conversation file a pane printed itself must not become a command.
        #expect(PaneConversation.from(transcript: "/Users/me/.claude/projects/x/a;rm -rf ~.jsonl") == nil)
        #expect(PaneConversation(agent: "claude", id: "x; rm -rf ~").resumeCommand == nil)
        #expect(PaneConversation(agent: "gemini", id: id).resumeCommand == nil)
    }
}

struct LastSessionTests {
    private func session(windows: Int = 2, canvas: Bool = false, panes: Int = 3, claude: Int = 1) -> LastSession {
        var groups = (0..<windows).map { _ in
            WindowSnapshot.Group(frame: .zero, selected: 0, miniaturized: false, tabs: [Data("{}".utf8)])
        }
        if canvas {
            groups.append(.init(frame: .zero, selected: 0, miniaturized: false, tabs: [],
                                canvas: .init(state: Data("{}".utf8), fullscreen: false)))
        }
        let ids = (0..<panes).map { _ in UUID().uuidString }
        let conversations = Dictionary(uniqueKeysWithValues: ids.prefix(claude).map {
            ($0, PaneConversation(agent: "claude", id: UUID().uuidString))
        })
        return LastSession(at: Date(timeIntervalSince1970: 2_000_000_000), windows: WindowSnapshot(groups: groups),
                           panes: ids, conversations: conversations)
    }

    @Test func overWhenNoPanesSessionSurvived() {
        let last = session()
        #expect(last.isOver(liveSurfaces: []))
        #expect(last.isOver(liveSurfaces: ["someone-elses-pane"]))
    }

    @Test func notOverWhenAPanesSessionIsStillRunning() {
        // Lostty crashed and tmux lives on: the crash's "Reopen?" applies.
        let last = session()
        #expect(!last.isOver(liveSurfaces: [last.panes[1]]))
    }

    @Test func anEmptySessionIsNeverOffered() {
        #expect(!session(windows: 0, panes: 0, claude: 0).isOver(liveSurfaces: []))
    }

    @Test func theSummaryCountsWindowsTerminalsAndConversations() {
        #expect(session(windows: 3, canvas: true, panes: 9, claude: 4).summary
            == "3 windows and the canvas · 9 terminals · 4 Claude conversations")
        #expect(session(windows: 1, panes: 1, claude: 0).summary == "1 window · 1 terminal")
        #expect(session(windows: 0, canvas: true, panes: 2, claude: 1).summary
            == "the canvas · 2 terminals · 1 Claude conversation")
    }

    @Test func savesAndLoads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("last-session-\(UUID().uuidString)").appendingPathComponent("last.json")
        let last = session(canvas: true)
        try last.save(to: url)
        #expect(LastSession.load(from: url) == last)
        LastSession.delete(at: url)
        #expect(LastSession.load(from: url) == nil)
    }

    @Test func aNewSaveTimeIsNotAChange() {
        let last = session()
        var later = last
        later.at = last.at.addingTimeInterval(60)
        #expect(last.sameContents(as: later))
        later.conversations = [:]
        #expect(!last.sameContents(as: later))
    }
}
#endif
