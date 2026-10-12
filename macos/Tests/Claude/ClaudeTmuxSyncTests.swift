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

    @Test func otherLosttysAndPaneLessSessionsAreLeftAlone() {
        let sessions = [session("$1", a, owner: 200, claude: nil), session("$2", nil, owner: 100, claude: .working)]
        #expect(ClaudeTmuxSync.args(desired: [a.uuidString: .working], sessions: sessions, pid: 100).isEmpty)
    }
}
#endif
