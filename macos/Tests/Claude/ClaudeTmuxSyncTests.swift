#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Ghostty

struct ClaudeTmuxSyncTests {
    let a = UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000001")!
    let b = UUID(uuidString: "ABCDEF02-0000-4000-8000-000000000002")!

    func session(_ id: String, _ pane: UUID?, owner: Int32?, claude: ClaudeActivity?) -> RemoteSession {
        RemoteSession(id: id, name: "p", surface: pane?.uuidString, owner: owner, claude: claude)
    }

    @Test func onlySubagentsWorkingSaysSo() {
        #expect(ClaudeTmuxSync.desired(phases: [a, b], awaiting: [], subagents: [b])
            == [a.uuidString: .working, b.uuidString: .subagents])
        let since = Date()
        #expect(ClaudeTmuxSync.subagents([a: .racing(since: since), b: .racing(since: since, subagents: true)]) == [b])
        #expect(ClaudeActivity(rawValue: "agents") == .subagents)
    }

    @Test func waitingBeatsWorking() {
        #expect(ClaudeTmuxSync.desired(phases: [a, b], awaiting: [a]) == [a.uuidString: .waiting, b.uuidString: .working])
    }

    @Test func writesOnlyWhatChangedThenSignals() {
        let sessions = [session("$1", a, owner: 100, claude: nil), session("$2", b, owner: 100, claude: .working)]
        #expect(ClaudeTmuxSync.args(desired: [a.uuidString: .waiting], sessions: sessions, pid: 100) == [
            "set-option", "-t", "$1", "@lostty_claude", "waiting", ";",
            "set-option", "-u", "-t", "$2", "@lostty_claude", ";",
            "wait-for", "-S", "lostty-changed",
        ])
    }

    @Test func nothingToWriteWhenTmuxAlreadyAgrees() {
        let sessions = [session("$1", a, owner: 100, claude: .waiting), session("$2", b, owner: 100, claude: nil)]
        #expect(ClaudeTmuxSync.args(desired: [a.uuidString: .waiting], sessions: sessions, pid: 100).isEmpty)
    }

    @Test func aGoneLosttysClaudeStateIsCleared() {
        // 300 crashed; $2 was let go (or made on the phone); 200 still runs.
        let sessions = [
            session("$1", a, owner: 300, claude: .waiting),
            session("$2", nil, owner: nil, claude: .working),
            session("$3", b, owner: 200, claude: .working),
        ]
        #expect(ClaudeTmuxSync.args(desired: [:], sessions: sessions, pid: 100, isAlive: { $0 == 100 || $0 == 200 }) == [
            "set-option", "-u", "-t", "$1", "@lostty_claude", ";",
            "set-option", "-u", "-t", "$2", "@lostty_claude", ";",
            "wait-for", "-S", "lostty-changed",
        ])
    }

    @Test func aGoneLosttysSessionWithoutClaudeStateIsNotWritten() {
        let sessions = [session("$1", a, owner: 300, claude: nil), session("$2", nil, owner: nil, claude: nil)]
        #expect(ClaudeTmuxSync.args(desired: [:], sessions: sessions, pid: 100, isAlive: { $0 == 100 }).isEmpty)
    }

    @Test func otherLosttysAndPaneLessSessionsAreLeftAlone() {
        let sessions = [session("$1", a, owner: 200, claude: nil), session("$2", nil, owner: 100, claude: .working)]
        #expect(ClaudeTmuxSync.args(desired: [a.uuidString: .working], sessions: sessions, pid: 100).isEmpty)
    }

    @Test func actionsGoOnlyToPanesWorkingOrWaitingInOneLine() {
        let c = UUID()
        let actions = [a: "Editing\tFoo.swift", b: "Reading Bar.swift", c: "Stale"]
        #expect(ClaudeTmuxSync.desiredActions(actions, showing: [a.uuidString, b.uuidString]) == [
            a.uuidString: "Editing Foo.swift", b.uuidString: "Reading Bar.swift",
        ])
    }
}
#endif
