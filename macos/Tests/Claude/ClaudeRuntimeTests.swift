#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct ClaudeRuntimeTests {
    final class Harness {
        var clock = Date(timeIntervalSince1970: 1_000)
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    }

    let harness = Harness()
    let pane = UUID()

    func makeRuntime() -> ClaudeRuntime {
        let harness = self.harness
        return ClaudeRuntime(
            now: { harness.clock },
            schedule: { delay, work in harness.pending.append((delay, work)) })
    }

    /// What the core delivers: the decoded JSON text.
    func payload(_ state: String) -> String {
        #"{"v":1,"state":"\#(state)"}"#
    }

    /// Advances the clock past every scheduled settle and runs them.
    func runPending() {
        let work = harness.pending
        harness.pending = []
        for item in work {
            harness.clock = harness.clock.addingTimeInterval(item.delay)
            item.work()
        }
    }

    @Test func busyUserVarStartsRacing() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("busy"))
        #expect(runtime.phase(pane) == .racing(since: harness.clock))
    }

    @Test func otherUserVarsAndGarbageAreIgnored() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: "GHOSTTY_SKIN", value: payload("busy"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: "garbage")
        #expect(runtime.phase(pane) == .off)
        #expect(runtime.phases.isEmpty)
    }

    @Test func idleFinishesThenSettlesOff() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        guard case .finishing = runtime.phase(pane) else { Issue.record("expected finishing"); return }
        // The finish settle is scheduled (busy also schedules an idle-title check).
        #expect(harness.pending.contains { $0.delay >= TraceTiming.finishTotal })
        runPending()
        #expect(runtime.phase(pane) == .off)
        #expect(runtime.phases[pane] == nil)
    }

    @Test func newPromptDuringFlashKeepsRacing() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        let start = harness.clock
        runtime.apply(.idle, to: pane)
        runtime.apply(.busy, to: pane)
        runPending()
        #expect(runtime.phase(pane) == .racing(since: start))
    }

    @Test func commandFinishedFadesARacingTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.commandFinished(pane)
        guard case .fading = runtime.phase(pane) else { Issue.record("expected fading"); return }
        runPending()
        #expect(runtime.phase(pane) == .off)
    }

    @Test func commandFinishedOnAnIdlePaneDoesNothing() {
        let runtime = makeRuntime()
        runtime.commandFinished(pane)
        #expect(runtime.phases.isEmpty)
        #expect(harness.pending.isEmpty)
    }

    @Test func panesAreIndependent() {
        let runtime = makeRuntime()
        let other = UUID()
        runtime.apply(.busy, to: pane)
        #expect(runtime.phase(other) == .off)
    }

    // Esc interrupts never send Stop; Claude's title shows ✳ when idle and a
    // spinner while working, so a racing pane idle-titled for the grace
    // period fades out (no finish flash: it was interrupted, not done).
    @Test func idleTitleAfterGraceFadesARacingTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "✳ My session")
        runPending()
        guard case .fading = runtime.phase(pane) else { Issue.record("expected fading, got \(runtime.phase(pane))"); return }
    }

    @Test func spinnerTitleCancelsTheIdleCheck() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "✳ My session")
        runtime.titleChanged(pane, title: "◐ My session")
        runPending()
        guard case .racing = runtime.phase(pane) else { Issue.record("expected racing, got \(runtime.phase(pane))"); return }
    }

    @Test func idleTitleAlreadyShowingWhenBusyArrives() {
        let runtime = makeRuntime()
        runtime.titleChanged(pane, title: "✳ My session")
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "◑ My session")
        runPending()
        guard case .racing = runtime.phase(pane) else { Issue.record("expected racing, got \(runtime.phase(pane))"); return }
    }

    @Test func idleTitleDoesNotPreemptAStopThatArrives() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "✳ My session")
        runtime.apply(.idle, to: pane)
        guard case .finishing = runtime.phase(pane) else { Issue.record("expected finishing"); return }
    }

    @Test func otherTitlesNeverEndATrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "vim notes.txt")
        runPending()
        guard case .racing = runtime.phase(pane) else { Issue.record("expected racing"); return }
    }

    @Test func settleAfterCloseDoesNothing() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        runtime.surfaceClosed(pane)
        runPending()
        #expect(runtime.phases[pane] == nil)
    }
}
#endif
