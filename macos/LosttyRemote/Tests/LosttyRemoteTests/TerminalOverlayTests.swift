import Foundation
import Testing
@testable import LosttyRemote

struct TerminalOverlayTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func aDropShowsReconnectingAndAReattachClearsIt() {
        let lost = TerminalOverlay.none.after(.lost, now: t0)
        #expect(lost == .reconnecting(since: t0))
        #expect(lost.message == "Connection lost — reconnecting…")
        #expect(lost.isReconnecting)
        // Another failed try keeps the original start, for the 30 s clock.
        #expect(lost.after(.lost, now: t0.addingTimeInterval(20)) == .reconnecting(since: t0))
        #expect(lost.after(.attached, now: t0.addingTimeInterval(21)) == .none)
    }

    @Test func backToSessionsAfterThirtySeconds() {
        let reconnecting = TerminalOverlay.reconnecting(since: t0)
        #expect(!reconnecting.offersBack(now: t0.addingTimeInterval(29)))
        #expect(reconnecting.offersBack(now: t0.addingTimeInterval(30)))
        #expect(TerminalOverlay.closed("Closed on your Mac").offersBack(now: t0))
        #expect(!TerminalOverlay.none.offersBack(now: t0))
    }

    @Test func aClosedOverlayStaysUntilTapped() {
        let closed = TerminalOverlay.closed("Closed on your Mac")
        #expect(closed.message == "Closed on your Mac")
        for status in [RemoteLinkStatus.attached, .lost, .stopped, .exited(0)] {
            #expect(closed.after(status, now: t0) == closed)
        }
    }

    @Test func givingUpWithAMessageClearsTheOverlaySoTheMessageShows() {
        #expect(TerminalOverlay.reconnecting(since: t0).after(.stopped, now: t0) == .none)
    }

    @Test func withoutAnOverlayOnlyADropChangesAnything() {
        #expect(TerminalOverlay.none.after(.attached, now: t0) == .none)
        #expect(TerminalOverlay.none.after(.exited(0), now: t0) == .none)
        #expect(TerminalOverlay.none.message == nil)
    }
}
