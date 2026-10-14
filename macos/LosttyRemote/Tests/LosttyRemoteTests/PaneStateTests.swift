import Foundation
import Testing
@testable import LosttyRemote

struct PaneStateTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func waitingOnYouComesFirstThenWorking() {
        #expect(PaneState(waiting: true, working: true, lastActivity: now, now: now) == .waiting)
        #expect(PaneState(waiting: false, working: true, lastActivity: nil, now: now) == .working)
    }

    @Test func readyWhileTypedIntoLatelyThenIdle() {
        let lately = now.addingTimeInterval(-(SessionLabel.idleAfter - 1))
        let long = now.addingTimeInterval(-SessionLabel.idleAfter)
        #expect(PaneState(waiting: false, working: false, lastActivity: lately, now: now) == .ready)
        #expect(PaneState(waiting: false, working: false, lastActivity: long, now: now) == .idle)
        #expect(PaneState(waiting: false, working: false, lastActivity: nil, now: now) == .idle)
    }

    @Test func titles() {
        #expect([PaneState.waiting, .working, .ready, .idle].map(\.title)
            == ["Waiting on you", "Working\u{2026}", "Ready", "Idle"])
    }
}
