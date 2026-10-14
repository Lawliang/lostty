import Foundation
import Testing
@testable import LosttyRemote

struct WorkingLineCheckTests {
    private let pane = UUID()
    private let start = Date(timeIntervalSince1970: 1_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func twoChecksInARowWithoutTheLineStopIt() {
        var check = WorkingLineCheck()
        #expect(check.check(racing: [pane: start], showing: [pane: false], now: at(10)).isEmpty)
        #expect(check.check(racing: [pane: start], showing: [pane: false], now: at(12)) == [pane])
    }

    @Test func theLineShowingAgainStartsTheCountOver() {
        var check = WorkingLineCheck()
        _ = check.check(racing: [pane: start], showing: [pane: false], now: at(10))
        _ = check.check(racing: [pane: start], showing: [pane: true], now: at(12))
        #expect(check.check(racing: [pane: start], showing: [pane: false], now: at(14)).isEmpty)
    }

    @Test func aYoungTurnHasTimeToShowItsLine() {
        var check = WorkingLineCheck()
        #expect(check.check(racing: [pane: start], showing: [pane: false], now: at(2)).isEmpty)
        #expect(check.check(racing: [pane: start], showing: [pane: false], now: at(4)).isEmpty)
        #expect(check.check(racing: [pane: start], showing: [pane: false], now: at(6)).isEmpty)
        #expect(check.check(racing: [pane: start], showing: [pane: false], now: at(8)) == [pane])
    }

    @Test func aPaneNotReadCountsForNothing() {
        var check = WorkingLineCheck()
        _ = check.check(racing: [pane: start], showing: [pane: false], now: at(10))
        #expect(check.check(racing: [pane: start], showing: [:], now: at(12)).isEmpty)
        #expect(check.check(racing: [pane: start], showing: [pane: false], now: at(14)) == [pane])
    }

    @Test func aTraceThatEndedForgetsItsMisses() {
        var check = WorkingLineCheck()
        _ = check.check(racing: [pane: start], showing: [pane: false], now: at(10))
        _ = check.check(racing: [:], showing: [:], now: at(12))
        #expect(check.check(racing: [pane: at(12)], showing: [pane: false], now: at(20)).isEmpty)
    }
}
