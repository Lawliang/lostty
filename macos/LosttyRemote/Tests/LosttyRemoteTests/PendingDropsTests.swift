import Foundation
import Testing
@testable import LosttyRemote

struct PendingDropsTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    /// Two unread build notes, as the Mac's file has them.
    func macLog() -> NoteLog {
        var log = NoteLog()
        for build in ["1", "2"] {
            log.apply(
                .build(
                    NoteBuild(app: "Lostty", bundleID: "b", build: build, commit: "c", branch: "main", project: "p", installURL: "u"),
                    sessionID: nil, terminal: nil, skin: nil),
                now: now)
        }
        return log
    }

    @Test func aChangeNotYetSentStaysOverTheMacsNotes() {
        var pending = PendingDrops()
        let mac = macLog()
        _ = pending.add(.delete([mac.notes[0].id]))
        let shown = pending.overlay(mac, now: now.addingTimeInterval(30))
        #expect(shown.notes.count == 1)
    }

    @Test func aSentChangeStaysUntilTheMacHasHadTimeToApplyIt() {
        var pending = PendingDrops()
        let mac = macLog()
        let id = pending.add(.readAll)
        pending.sent(id, at: now)
        #expect(pending.overlay(mac, now: now.addingTimeInterval(1)).unreadCount == 0)
        // Long enough: the Mac's file is the truth again.
        #expect(pending.overlay(mac, now: now.addingTimeInterval(PendingDrops.settle + 1)).unreadCount == 2)
        #expect(pending.isEmpty)
    }

    @Test func aFailedChangeIsDropped() {
        var pending = PendingDrops()
        let mac = macLog()
        let id = pending.add(.readAll)
        pending.failed(id)
        #expect(pending.overlay(mac, now: now).unreadCount == 2)
    }
}
