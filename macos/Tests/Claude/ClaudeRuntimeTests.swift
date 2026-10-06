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

    @Test func idleStopsTheTraceAtOnce() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        #expect(runtime.phase(pane) == .off)
        #expect(runtime.phases.isEmpty)
    }

    @Test func commandFinishedStopsARacingTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.commandFinished(pane)
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
    // period stops.
    @Test func idleTitleAfterGraceStopsARacingTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "✳ My session")
        runPending()
        #expect(runtime.phase(pane) == .off)
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

    @Test func stopDuringAPendingIdleCheckStaysOff() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "✳ My session")
        runtime.apply(.idle, to: pane)
        runPending()
        #expect(runtime.phase(pane) == .off)
    }

    // Codex: a braille spinner while working, the plain folder name when
    // idle, and no Stop hook after Esc. Once a spinner was seen, a title
    // without one for the grace period ends the trace.
    @Test func codexSpinnerThenPlainTitleStopsTheTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "⠋ codexproj")
        runtime.titleChanged(pane, title: "codexproj")
        runPending()
        #expect(runtime.phase(pane) == .off)
    }

    @Test func spinnerComingBackCancelsTheCodexCheck() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "⠋ codexproj")
        runtime.titleChanged(pane, title: "codexproj")
        runtime.titleChanged(pane, title: "⠙ codexproj")
        runPending()
        guard case .racing = runtime.phase(pane) else { Issue.record("expected racing"); return }
    }

    @Test func recognizesBothSpinners() {
        #expect(ClaudeRuntime.isSpinner("◐ My session"))
        #expect(ClaudeRuntime.isSpinner("⠦ codexproj"))
        #expect(!ClaudeRuntime.isSpinner("✳ My session"))
        #expect(!ClaudeRuntime.isSpinner("codexproj"))
    }

    @Test func otherTitlesNeverEndATrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "vim notes.txt")
        runPending()
        guard case .racing = runtime.phase(pane) else { Issue.record("expected racing"); return }
    }

    // "Ready for response": Claude finished (or asks permission) while the
    // pane is not focused; focusing it clears the overlay for that turn.
    @Test func finishWhileUnfocusedAwaitsResponse() {
        let runtime = makeRuntime()
        runtime.focusChanged(pane, focused: false)
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        #expect(runtime.awaiting.contains(pane))
    }

    @Test func finishWhileFocusedDoesNotAwait() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        #expect(runtime.awaiting.isEmpty)
        // Leaving afterwards does not bring it back: it was seen.
        runtime.focusChanged(pane, focused: false)
        #expect(runtime.awaiting.isEmpty)
    }

    @Test func focusingClearsAndALaterNotificationDoesNotReshow() {
        let runtime = makeRuntime()
        runtime.focusChanged(pane, focused: false)
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        runtime.focusChanged(pane, focused: true)
        #expect(runtime.awaiting.isEmpty)
        runtime.focusChanged(pane, focused: false)
        runtime.apply(.idle, to: pane) // e.g. Claude's 60s idle notification
        #expect(runtime.awaiting.isEmpty)
    }

    @Test func newWorkMakesTheNextFinishShowAgain() {
        let runtime = makeRuntime()
        runtime.focusChanged(pane, focused: false)
        runtime.apply(.idle, to: pane)
        runtime.focusChanged(pane, focused: true)
        runtime.focusChanged(pane, focused: false)
        // Claude resumes (a new prompt, or work after a permission prompt).
        runtime.titleChanged(pane, title: "◐ My session")
        runtime.apply(.idle, to: pane)
        #expect(runtime.awaiting.contains(pane))
        runtime.focusChanged(pane, focused: true)
        runtime.focusChanged(pane, focused: false)
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        #expect(runtime.awaiting.contains(pane))
    }

    @Test func busyExitAndCloseClearAwaiting() {
        let runtime = makeRuntime()
        runtime.focusChanged(pane, focused: false)
        runtime.apply(.idle, to: pane)
        runtime.apply(.busy, to: pane)
        #expect(runtime.awaiting.isEmpty)
        runtime.apply(.idle, to: pane)
        runtime.commandFinished(pane)
        #expect(runtime.awaiting.isEmpty)
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        runtime.surfaceClosed(pane)
        #expect(runtime.awaiting.isEmpty)
    }

    @Test func pendingCheckAfterCloseDoesNothing() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "✳ My session")
        runtime.surfaceClosed(pane)
        runPending()
        #expect(runtime.phases[pane] == nil)
    }

}
#endif
