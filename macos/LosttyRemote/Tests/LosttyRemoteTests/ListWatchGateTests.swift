import Foundation
import Testing
@testable import LosttyRemote

struct ListWatchGateTests {
    func visible() -> ListWatchGate {
        var gate = ListWatchGate()
        gate.listVisible = true
        return gate
    }

    @Test func runsWhileTheListIsVisibleTheAppActiveAndAMacPaired() {
        #expect(visible().wanted(hasHosts: true))
        #expect(!visible().wanted(hasHosts: false))
        #expect(!ListWatchGate().wanted(hasHosts: true))
    }

    @Test func aCancelledFaceIDStaysStoppedThroughInactiveAndActive() {
        var gate = visible()
        let stopped = gate.watchFailed(RemoteError.authenticationCancelled)
        #expect(stopped)
        // The Face ID sheet itself makes the app inactive, then active.
        gate.becameActive(afterBackground: false)
        #expect(!gate.wanted(hasHosts: true))
    }

    @Test func askingAgainStartsItAgain() {
        var gate = visible()
        _ = gate.watchFailed(RemoteError.keyRejected)
        gate.userAsked()
        #expect(gate.wanted(hasHosts: true))
    }

    @Test func aRealTripToTheBackgroundStartsItAgain() {
        var gate = visible()
        _ = gate.watchFailed(RemoteError.authenticationCancelled)
        gate.wentToBackground()
        #expect(!gate.wanted(hasHosts: true))
        gate.becameActive(afterBackground: true)
        #expect(gate.wanted(hasHosts: true))
    }

    @Test func aPassingErrorKeepsItRunning() {
        var gate = visible()
        let tmuxMissing = gate.watchFailed(RemoteError.tmuxMissing)
        let offline = gate.watchFailed(URLError(.notConnectedToInternet))
        #expect(!tmuxMissing && !offline)
        gate.becameActive(afterBackground: false)
        #expect(gate.wanted(hasHosts: true))
    }
}

struct RenameFailureTests {
    let current = RemoteSession(id: "$3", name: "api", surface: nil, owner: nil, label: "Deploy")

    @Test func aSessionNoLongerListedHasEnded() {
        #expect(RenameFailure.after(sessionID: "$3", listed: []) == .ended)
        #expect(RenameFailure.ended.message == "Couldn't rename: that session has ended.")
    }

    @Test func aSessionStillListedChangedOnTheMac() {
        #expect(RenameFailure.after(sessionID: "$3", listed: [current]) == .changed)
        #expect(RenameFailure.changed.message == "Couldn't rename: the session changed on your Mac. Try again.")
    }

    @Test func theCurrentSessionIsFoundByID() {
        let opened = RemoteSession(id: "$3", name: "lostty", surface: nil, owner: nil)
        #expect(RemoteSession.current(of: opened, in: [current]) == current)
        #expect(RemoteSession.current(of: opened, in: []) == nil)
    }
}
