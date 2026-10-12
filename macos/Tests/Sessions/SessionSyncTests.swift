#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Ghostty

private let paneA = UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000001")!
private let paneB = UUID(uuidString: "ABCDEF02-0000-4000-8000-000000000002")!

struct SessionSyncTests {
    let sessions = [
        RemoteSession(id: "$1", name: "a", surface: paneA.uuidString, owner: 100, label: "Deploy"),
        RemoteSession(id: "$2", name: "b", surface: paneB.uuidString, owner: 200, label: "Other Lostty"),
        RemoteSession(id: "$3", name: "c", surface: nil, owner: nil, label: "Made on the phone"),
        RemoteSession(id: "$4", name: "d", surface: "not-a-uuid", owner: 100, label: "Junk"),
        RemoteSession(id: "$5", name: "e", surface: paneB.uuidString, owner: 100, label: nil),
    ]

    @Test func labelsAreThisLosttysPanes() {
        #expect(SessionSync.labels(sessions, pid: 100) == [paneA: "Deploy"])
    }

    @Test func onlyANewAttachCountsAsSeeing() {
        #expect(SessionSync.newlyAttached(previous: [], current: ["$1"]) == ["$1"])
        // A phone left attached hides nothing later.
        #expect(SessionSync.newlyAttached(previous: ["$1"], current: ["$1", "$2"]) == ["$2"])
        #expect(SessionSync.newlyAttached(previous: ["$1", "$2"], current: ["$1"]).isEmpty)
        // Leaving and attaching again is a new attach.
        #expect(SessionSync.newlyAttached(previous: ["$2"], current: ["$1"]) == ["$1"])
    }

    @Test func aPhoneOnOneOfOurSessionsNamesItsPane() {
        #expect(SessionSync.panesWithAPhone(sessions, phoneAttached: ["$1", "$2", "$3"], pid: 100) == [paneA])
    }
}

struct SessionTitleOverrideTests {
    @Test func aLabelBecomesTheTabTitle() {
        #expect(SessionTitleOverride.next(current: nil, fromLabel: false, label: "Deploy")
            == SessionTitleOverride(title: "Deploy", fromLabel: true))
    }

    @Test func clearingALabelClearsTheTitleItSet() {
        #expect(SessionTitleOverride.next(current: "Deploy", fromLabel: true, label: nil)
            == SessionTitleOverride(title: nil, fromLabel: false))
    }

    @Test func aTitleTypedForAPlainPaneStays() {
        #expect(SessionTitleOverride.next(current: "Notes", fromLabel: false, label: nil)
            == SessionTitleOverride(title: "Notes", fromLabel: false))
    }
}
#endif
