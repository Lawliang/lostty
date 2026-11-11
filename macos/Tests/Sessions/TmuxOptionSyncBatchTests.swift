#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

/// Every option synced at once goes to tmux in one call with one signal:
/// each tmux call is a process, and a tmux change syncs them all.
struct TmuxOptionSyncBatchTests {
    let mine = RemoteSession(id: "$1", name: "lostty", surface: "PANE", owner: 1)

    func wish(_ value: String?, current: @escaping @Sendable (RemoteSession) -> String?) -> TmuxOptionSync.Wish {
        TmuxOptionSync.Wish(desired: value.map { ["PANE": $0] } ?? [:], current: current)
    }

    @Test func optionsThatDifferShareOneCallAndOneSignal() {
        let args = TmuxOptionSync.args(
            [
                TmuxRemote.claudeOption: wish("working") { $0.claude?.rawValue },
                TmuxRemote.actionOption: wish("Run the tests") { $0.action },
            ],
            sessions: [mine], pid: 1)
        #expect(args == [
            "set-option", "-t", "$1", TmuxRemote.actionOption, "Run the tests", ";",
            "set-option", "-t", "$1", TmuxRemote.claudeOption, "working", ";",
        ] + TmuxHooks.signalCommand)
    }

    @Test func nothingIsWrittenOrSignalledWhenTmuxAgrees() {
        var session = mine
        session.claude = .working
        let args = TmuxOptionSync.args(
            [
                TmuxRemote.claudeOption: wish("working") { $0.claude?.rawValue },
                TmuxRemote.actionOption: wish(nil) { $0.action },
            ],
            sessions: [session], pid: 1)
        #expect(args.isEmpty)
    }

    @Test func onlyTheOptionThatDiffersIsWritten() {
        var session = mine
        session.claude = .working
        let args = TmuxOptionSync.args(
            [
                TmuxRemote.claudeOption: wish("working") { $0.claude?.rawValue },
                TmuxRemote.actionOption: wish("Edit") { $0.action },
            ],
            sessions: [session], pid: 1)
        #expect(args == ["set-option", "-t", "$1", TmuxRemote.actionOption, "Edit", ";"] + TmuxHooks.signalCommand)
    }
}

/// The plain listing the phone's notes read stands in for the listing
/// script, which reports a session of a Lostty that is gone as not open.
struct NotesListingTests {
    @Test func aSessionOfALosttyThatIsGoneIsNotOpenOnTheMac() {
        let session = RemoteSession(id: "$1", name: "lostty", surface: "PANE", owner: 77, claude: .waiting)
        #expect(NotesKeeper.withoutDeadOwner(session, isAlive: { _ in false }).owner == nil)
        #expect(NotesKeeper.withoutDeadOwner(session, isAlive: { _ in true }).owner == 77)
    }
}
#endif
