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

    @Test func anHugeServerExitStatusDoesNotTrap() {
        let outcome = AttachOutcome()
        outcome.record(remoteEnded: true, exitCode: Int(Int32.max) + 5)
        #expect(outcome.end(afterError: nil) == .exited(Int32(truncatingIfNeeded: Int(Int32.max) + 5)))
        #expect(AttachEnd.from(finished: true, exitCode: Int(Int32.max) + 5) == .exited(Int32(truncatingIfNeeded: Int(Int32.max) + 5)))
    }

    @Test func firstOutcomeWins() {
        let outcome = AttachOutcome()
        outcome.recordClosedLocally()
        outcome.record(remoteEnded: true, exitCode: 3)
        #expect(outcome.end(afterError: nil) == .exited(0))
    }
}
