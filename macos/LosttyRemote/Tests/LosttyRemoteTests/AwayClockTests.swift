import Foundation
import Testing
@testable import LosttyRemote

struct AwayClockTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func awayThirtyMinutesAfterTheLastUse() {
        let clock = AwayClock(now: start)
        #expect(!clock.isAway(now: start.addingTimeInterval(29 * 60)))
        #expect(clock.isAway(now: start.addingTimeInterval(30 * 60)))
    }

    @Test func eachUseStartsTheThirtyMinutesOver() {
        var clock = AwayClock(now: start)
        clock.used(at: start.addingTimeInterval(25 * 60))
        #expect(!clock.isAway(now: start.addingTimeInterval(50 * 60)))
        #expect(clock.restsAt == start.addingTimeInterval(55 * 60))
    }

    @Test func anEarlierUseDoesNotWindItBack() {
        var clock = AwayClock(now: start)
        clock.used(at: start.addingTimeInterval(-60))
        #expect(clock.lastUsed == start)
    }
}
