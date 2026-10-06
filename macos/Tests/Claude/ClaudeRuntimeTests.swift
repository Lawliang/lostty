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

    func payload(_ state: String) -> String {
        Data(#"{"v":1,"state":"\#(state)"}"#.utf8).base64EncodedString()
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
        #expect(harness.pending.count == 1)
        #expect(harness.pending[0].delay >= TraceTiming.finishTotal)
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
