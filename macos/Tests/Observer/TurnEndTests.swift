#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct TurnEndTests {
    @Test func theBetaTellsTheObserverAndTheUsageBreakdown() {
        var observed: [String] = []
        var reported: [String] = []
        let handler = TurnEnd.handler(channel: .beta, observe: { _, path in observed.append(path) },
                                      report: { reported.append($0) })
        handler(UUID(), "/t.jsonl")
        #expect(observed == ["/t.jsonl"])
        #expect(reported == ["/t.jsonl"])
    }

    @Test func stableStillCountsUsageButNeverSummarizes() {
        var observed: [String] = []
        var reported: [String] = []
        let handler = TurnEnd.handler(channel: .stable, observe: { _, path in observed.append(path) },
                                      report: { reported.append($0) })
        handler(UUID(), "/t.jsonl")
        #expect(observed.isEmpty)
        #expect(reported == ["/t.jsonl"])
    }
}
#endif
