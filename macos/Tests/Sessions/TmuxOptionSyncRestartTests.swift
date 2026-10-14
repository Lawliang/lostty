#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

/// Restart to Update: in the moment between the old Lostty exiting and the
/// new one's panes reattaching, its sessions look abandoned. Their options
/// must not be cleared then (the phone's rows, the waiting notes).
struct TmuxOptionSyncRestartTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func orphan(owner: Int32 = 77) -> RemoteSession {
        RemoteSession(id: "$1", name: "lostty", surface: "PANE", owner: owner, claude: .waiting)
    }

    func args(_ restarting: TmuxOptionSync.Restarting?) -> [String] {
        TmuxOptionSync.args(
            option: TmuxRemote.claudeOption, desired: [:], current: { $0.claude?.rawValue },
            sessions: [orphan()], pid: 1, isAlive: { _ in false }, restarting: restarting, now: now)
    }

    @Test func aRestartingLosttysSessionsKeepTheirOptions() {
        #expect(args(TmuxOptionSync.Restarting(pid: 77, until: now.addingTimeInterval(20))).isEmpty)
    }

    @Test func otherwiseAnAbandonedSessionIsCleared() {
        #expect(!args(nil).isEmpty)
        #expect(!args(TmuxOptionSync.Restarting(pid: 77, until: now.addingTimeInterval(-1))).isEmpty)
        #expect(!args(TmuxOptionSync.Restarting(pid: 78, until: now.addingTimeInterval(20))).isEmpty)
    }

    @Test func theTagReadsAsPidAndDeadline() {
        #expect(TmuxOptionSync.Restarting(tag: "77 2000000030") == TmuxOptionSync.Restarting(pid: 77, until: Date(timeIntervalSince1970: 2_000_000_030)))
        #expect(TmuxOptionSync.Restarting(tag: "") == nil)
        #expect(TmuxOptionSync.Restarting(pid: 77, until: Date(timeIntervalSince1970: 2_000_000_030)).tag == "77 2000000030")
    }
}
#endif
