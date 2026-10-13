#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct SessionTitleSignalTests {
    final class Harness {
        var clock = Date(timeIntervalSince1970: 1_000)
        var signals = 0
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    }

    let harness = Harness()
    let pane = UUID()

    func make() -> SessionTitleSignal {
        let harness = self.harness
        return SessionTitleSignal(
            now: { harness.clock },
            schedule: { delay, work in harness.pending.append((delay, work)) },
            signal: { harness.signals += 1 })
    }

    func advance(_ seconds: TimeInterval) { harness.clock = harness.clock.addingTimeInterval(seconds) }

    @Test func spinnerFramesDoNotSignal() {
        let signal = make()
        signal.titleChanged(pane, title: "◐ Fix the login bug")
        advance(5)
        signal.titleChanged(pane, title: "◓ Fix the login bug")
        signal.titleChanged(pane, title: "✳ Fix the login bug")
        #expect(harness.signals == 1)
        #expect(harness.pending.isEmpty)
    }

    @Test func aNewTaskTitleSignals() {
        let signal = make()
        signal.titleChanged(pane, title: "◐ Fix the login bug")
        advance(5)
        signal.titleChanged(pane, title: "◐ Write the release notes")
        #expect(harness.signals == 2)
    }

    @Test func atMostOncePerSecond() {
        let signal = make()
        signal.titleChanged(pane, title: "◐ A")
        advance(0.2)
        signal.titleChanged(pane, title: "◐ B")
        advance(0.1)
        signal.titleChanged(pane, title: "◐ C")
        #expect(harness.signals == 1)
        #expect(harness.pending.count == 1)
        #expect(abs((harness.pending.first?.delay ?? 0) - 0.8) < 0.0001)
        advance(0.7)
        harness.pending.removeFirst().work()
        #expect(harness.signals == 2)
    }

    @Test func plainShellTitlesNeverSignal() {
        let signal = make()
        signal.titleChanged(pane, title: "~/projectrepos/lostty")
        advance(5)
        signal.titleChanged(pane, title: "~/projectrepos/lostty/macos")
        #expect(harness.signals == 0)
    }

    @Test func leavingClaudeSignals() {
        let signal = make()
        signal.titleChanged(pane, title: "✳ Fix the login bug")
        advance(5)
        signal.titleChanged(pane, title: "~/projectrepos/lostty")
        #expect(harness.signals == 2)
    }
}
#endif
