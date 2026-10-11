import Testing
@testable import LosttyRemote

struct AttachEndTests {
    @Test func aChannelThatFinishesIsAnExit() {
        #expect(AttachEnd.from(finished: true, exitCode: nil) == .exited(0))
        #expect(AttachEnd.from(finished: true, exitCode: 1) == .exited(1))
    }

    @Test func aChannelThatBrokeIsLost() {
        #expect(AttachEnd.from(finished: false, exitCode: nil) == .lost)
    }

    @Test func backoffGrowsToACapAndResets() {
        var policy = ReconnectPolicy()
        let delays = (0..<8).map { _ in policy.nextDelay() }
        #expect(delays == [0.5, 1, 2, 4, 8, 15, 15, 15])
        policy.reset()
        #expect(policy.nextDelay() == 0.5)
    }
}
