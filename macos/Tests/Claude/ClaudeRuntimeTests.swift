#if os(macOS)
import Foundation
import Testing
@testable import Lostty

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

    func action(_ text: String) -> String {
        #"{"v":1,"state":"tool","action":"\#(text)"}"#
    }

    @Test func aToolCallsActionShowsWhileWorkingAndLeavesWithTheTurn() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("busy"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: action("Reading Foo.swift"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: action("Editing Foo.swift"))
        #expect(runtime.actions[pane] == "Editing Foo.swift")
        // An action is no state change.
        #expect(runtime.phases[pane] != nil)
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("agents"))
        #expect(runtime.actions[pane] == "Editing Foo.swift")
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("idle"))
        #expect(runtime.actions[pane] == nil)
    }

    @Test func aPermissionWaitKeepsTheActionItAsksFor() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("busy"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: action("Run the tests"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: #"{"v":1,"state":"idle","permission":true}"#)
        #expect(runtime.actions[pane] == "Run the tests")
        // A new prompt starts over.
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("busy"))
        #expect(runtime.actions[pane] == nil)
    }

    @Test func exitingOrClosingDropsTheAction() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: action("Editing Foo.swift"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("exit"))
        #expect(runtime.actions[pane] == nil)
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: action("Editing Foo.swift"))
        runtime.surfaceClosed(pane)
        #expect(runtime.actions[pane] == nil)
    }

    @Test func busyUserVarStartsRacing() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("busy"))
        #expect(runtime.phase(pane) == .racing(since: harness.clock))
    }

    @Test func otherUserVarsAndGarbageAreIgnored() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: "LOSTTY_SKIN", value: payload("busy"))
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

    // Esc interrupts send no Stop. Agents that title the pane with a spinner
    // while working stop at once when the title turns idle.
    @Test func idleTitleAfterASpinnerStopsARacingTraceImmediately() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "◐ My session")
        runtime.titleChanged(pane, title: "✳ My session")
        #expect(runtime.phase(pane) == .off)
    }

    // Claude Code 2.1 keeps "✳ …" while it works: a retitle mid-turn is no
    // stop.
    @Test func aStarTitleWithoutASpinnerKeepsTheTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "✳ Fix the login bug")
        guard case .racing = runtime.phase(pane) else { Issue.record("expected racing"); return }
    }

    // After a permission prompt Claude carries on with no new prompt: its
    // next tool call starts the trace again.
    @Test func aToolCallWhileStoppedStartsTheTrace() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: action("Editing Foo.swift"))
        guard case .racing = runtime.phase(pane) else { Issue.record("expected racing"); return }
        #expect(runtime.actions[pane] == "Editing Foo.swift")
    }

    // An interrupt (Esc, Ctrl+C) leaves Claude waiting for you.
    @Test func theWorkingLineGoingStopsTheTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.workingLineGone(pane)
        #expect(runtime.phase(pane) == .off)
    }

    @Test func theWorkingLineGoingWhileSubagentsWorkKeepsTheTrace() {
        let runtime = makeRuntime()
        runtime.apply(.agents, to: pane)
        runtime.workingLineGone(pane)
        guard case .racing = runtime.phase(pane) else { Issue.record("expected racing"); return }
    }

    @Test func spinnerTitleKeepsTheTraceRacing() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "◐ My session")
        guard case .racing = runtime.phase(pane) else { Issue.record("expected racing"); return }
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
    // without one ends the trace.
    @Test func codexSpinnerThenPlainTitleStopsTheTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "⠋ codexproj")
        runtime.titleChanged(pane, title: "codexproj")
        #expect(runtime.phase(pane) == .off)
    }

    @Test func noDelayedChecksAreScheduled() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "⠋ codexproj")
        runtime.titleChanged(pane, title: "codexproj")
        #expect(harness.pending.isEmpty)
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

    @Test func aPhoneAttachingCountsAsSeeingTheWait() {
        let runtime = makeRuntime()
        runtime.focusChanged(pane, focused: false)
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane)
        #expect(runtime.awaiting == [pane])
        runtime.seenElsewhere(pane)
        #expect(runtime.awaiting.isEmpty)
        // The same wait doesn't come back.
        runtime.apply(.idle, to: pane)
        #expect(runtime.awaiting.isEmpty)
    }

    // Subagents: Claude's Stop says its subagents are still working, so it
    // carries on by itself. The trace keeps going (on the bottom edge) and
    // nothing waits on the person until Claude really finishes.
    @Test func subagentsKeepTheTraceAndDoNotAwait() {
        let runtime = makeRuntime()
        let start = harness.clock
        runtime.focusChanged(pane, focused: false)
        runtime.apply(.busy, to: pane)
        harness.clock = harness.clock.addingTimeInterval(5)
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("agents"))
        #expect(runtime.phase(pane) == .racing(since: start, subagents: true))
        #expect(runtime.awaiting.isEmpty)
        runtime.apply(.idle, to: pane)
        #expect(runtime.phase(pane) == .off)
        #expect(runtime.awaiting.contains(pane))
    }

    @Test func idleTitleWhileOnlySubagentsWorkKeepsTheTrace() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.titleChanged(pane, title: "◐ My session")
        runtime.apply(.agents, to: pane)
        runtime.titleChanged(pane, title: "✳ My session")
        #expect(runtime.phase(pane) == .racing(since: harness.clock, subagents: true))
    }

    @Test func claudeTakingOverLeavesTheBottomEdge() {
        let runtime = makeRuntime()
        let start = harness.clock
        runtime.apply(.agents, to: pane)
        runtime.apply(.resumed, to: pane)
        #expect(runtime.phase(pane) == .racing(since: start))
        // Claude's own spinner says the same when no hook does.
        runtime.apply(.agents, to: pane)
        runtime.titleChanged(pane, title: "◐ My session")
        #expect(runtime.phase(pane) == .racing(since: start))
    }

    @Test func resumedWithNoTraceDoesNothing() {
        let runtime = makeRuntime()
        runtime.apply(.resumed, to: pane)
        #expect(runtime.phases.isEmpty)
    }

    // MARK: Restart

    @Test func carryReadsWhatThePanesShow() {
        let runtime = makeRuntime()
        let working = UUID(), agents = UUID(), waiting = UUID()
        runtime.apply(.busy, to: working)
        runtime.apply(.agents, to: agents)
        runtime.focusChanged(waiting, focused: false)
        runtime.apply(.busy, to: waiting)
        runtime.apply(.idle, to: waiting, permission: true)
        let carried = runtime.carry()
        #expect(carried[working]?.activity == .working)
        #expect(carried[agents]?.activity == .subagents)
        #expect(carried[waiting]?.activity == .waiting)
        #expect(carried.count == 3)
    }

    @Test func restoreShowsThemAgain() {
        let runtime = makeRuntime()
        let working = UUID(), agents = UUID(), waiting = UUID()
        runtime.restore([
            working: ClaudeCarry(activity: .working, action: "Editing Foo.swift"),
            agents: ClaudeCarry(activity: .subagents, action: nil),
            waiting: ClaudeCarry(activity: .waiting, action: "Run the iOS tests"),
        ])
        #expect(runtime.phase(working) == .racing(since: harness.clock))
        #expect(runtime.phase(agents) == .racing(since: harness.clock, subagents: true))
        #expect(runtime.awaiting == [waiting])
        #expect(runtime.actions == [working: "Editing Foo.swift", waiting: "Run the iOS tests"])
    }

    @Test func aCarryRoundTripsThroughJSON() throws {
        let carry = ClaudeCarry(activity: .waiting, action: "Run the iOS tests")
        #expect(try JSONDecoder().decode(ClaudeCarry.self, from: JSONEncoder().encode(carry)) == carry)
    }

    final class Ended {
        var turns: [(pane: UUID, path: String)] = []
    }

    @Test func anIdleWithATranscriptTellsTheObserver() {
        let runtime = makeRuntime()
        let ended = Ended()
        runtime.turnEnded = { ended.turns.append(($0, $1)) }
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("busy"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: #"{"v":1,"state":"idle","transcript":"/t.jsonl"}"#)
        // No transcript, or not an idle: nothing to observe.
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: payload("idle"))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: #"{"v":1,"state":"busy","transcript":"/t.jsonl"}"#)
        #expect(ended.turns.count == 1)
        #expect(ended.turns.first?.pane == pane)
        #expect(ended.turns.first?.path == "/t.jsonl")
        // The trace still saw the idle.
        #expect(runtime.phases[pane] != nil) // the last busy
    }

    @Test func aTranscriptWithoutATurnIsIgnored() {
        // Anything printed in a pane can carry LOSTTY_CLAUDE: an idle with no
        // turn before it (no busy) doesn't reach the observer.
        let runtime = makeRuntime()
        let ended = Ended()
        runtime.turnEnded = { ended.turns.append(($0, $1)) }
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: #"{"v":1,"state":"idle","transcript":"/t.jsonl"}"#)
        #expect(ended.turns.isEmpty)
    }

    @Test func handoffSignals() {
        let runtime = makeRuntime()
        var signals: [ContextHandoffSignal] = []
        runtime.handoffSignal = { _, signal in signals.append(signal) }
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: payload("busy"))
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName,
                               value: #"{"v":1,"state":"idle","transcript":"/t.jsonl"}"#)
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: payload("fresh"))
        runtime.commandFinished(pane)
        #expect(signals == [.prompted, .stopped(transcript: "/t.jsonl"), .fresh, .gone])
    }

    @Test func aPermissionPromptIsNoHandoffStop() {
        let runtime = makeRuntime()
        var signals: [ContextHandoffSignal] = []
        runtime.handoffSignal = { _, signal in signals.append(signal) }
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: payload("busy"))
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName,
                               value: #"{"v":1,"state":"idle","permission":true,"transcript":"/t.jsonl"}"#)
        #expect(signals == [.prompted])
    }

    @Test func aClearWithoutAHandoffIsSignalled() {
        let runtime = makeRuntime()
        var signals: [ContextHandoffSignal] = []
        runtime.handoffSignal = { _, signal in signals.append(signal) }
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: payload("cleared"))
        #expect(signals == [.cleared])
        #expect(runtime.phases[pane] == nil)
    }

    @Test func freshChangesNoPhase() {
        let runtime = makeRuntime()
        runtime.userVarChanged(pane, name: ClaudeConstants.userVarName, value: payload("fresh"))
        #expect(runtime.phases[pane] == nil)
    }
}
#endif
