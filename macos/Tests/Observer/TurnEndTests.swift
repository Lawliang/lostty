#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct TurnEndTests {
    @Test func anObserverThatIsOnHearsTheTurnAndTheUsageBreakdownCountsIt() {
        var observed: [String] = []
        var reported: [String] = []
        let handler = TurnEnd.handler(observes: true, observe: { _, path in observed.append(path) },
                                      report: { reported.append($0) })
        handler(UUID(), "/t.jsonl")
        #expect(observed == ["/t.jsonl"])
        #expect(reported == ["/t.jsonl"])
    }

    @Test func anObserverThatIsOffNeverSummarizesButUsageStillCounts() {
        var observed: [String] = []
        var reported: [String] = []
        let handler = TurnEnd.handler(observes: false, observe: { _, path in observed.append(path) },
                                      report: { reported.append($0) })
        handler(UUID(), "/t.jsonl")
        #expect(observed.isEmpty)
        #expect(reported == ["/t.jsonl"])
    }
}
#endif
