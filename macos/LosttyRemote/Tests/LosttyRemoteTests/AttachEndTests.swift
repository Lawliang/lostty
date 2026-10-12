import Foundation
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

    @Test func aWatchThatNeverDeliveredKeepsBackingOff() {
        var policy = ReconnectPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        // No tmux server: the watch ends at once; the delay keeps growing.
        policy.watchEnded(deliveredChange: false)
        #expect(policy.nextDelay() == 2)
        // A watch that heard changes was a healthy connection.
        policy.watchEnded(deliveredChange: true)
        #expect(policy.nextDelay() == 0.5)
    }

    @Test func onlyErrorsTheUserMustResolveStopTheWatch() {
        #expect(ReconnectPolicy.stopsWatch(for: RemoteError.authenticationCancelled))
        #expect(ReconnectPolicy.stopsWatch(for: RemoteError.keyRejected))
        #expect(ReconnectPolicy.stopsWatch(for: RemoteError.hostKeyChanged(host: "h", pinned: "a", offered: "b")))
        #expect(!ReconnectPolicy.stopsWatch(for: RemoteError.tmuxMissing))
        #expect(!ReconnectPolicy.stopsWatch(for: URLError(.notConnectedToInternet)))
    }
}
