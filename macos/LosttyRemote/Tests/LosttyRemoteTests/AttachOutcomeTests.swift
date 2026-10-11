import Foundation
import Testing
@testable import LosttyRemote

struct AttachOutcomeTests {
    struct Boom: Error {}

    @Test func cleanRemoteEndIsExitedZeroEvenIfCitadelThrowsAfter() {
        let outcome = AttachOutcome()
        outcome.record(remoteEnded: true, exitCode: 0)
        #expect(outcome.end(afterError: Boom()) == .exited(0))
    }

    @Test func failedRemoteExitKeepsItsCode() {
        let outcome = AttachOutcome()
        outcome.record(remoteEnded: true, exitCode: 1)
        #expect(outcome.end(afterError: Boom()) == .exited(1))
    }

    @Test func localCloseIsExitedZero() {
        let outcome = AttachOutcome()
        outcome.recordClosedLocally()
        #expect(outcome.end(afterError: nil) == .exited(0))
    }

    @Test func nothingRecordedWithAnErrorIsLost() {
        #expect(AttachOutcome().end(afterError: Boom()) == .lost)
    }

    @Test func firstOutcomeWins() {
        let outcome = AttachOutcome()
        outcome.recordClosedLocally()
        outcome.record(remoteEnded: true, exitCode: 3)
        #expect(outcome.end(afterError: nil) == .exited(0))
    }
}
