#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct SleepCandidateTests {
    let now = Date(timeIntervalSince1970: 100_000)

    func idle(minutes: Double) -> SleepCandidate {
        SleepCandidate(agent: .claude, idleSince: now.addingTimeInterval(-minutes * 60))
    }

    @Test func aClaudeIdleLongEnoughSleeps() {
        #expect(idle(minutes: 20).qualifies(now: now, minutes: 20))
        #expect(idle(minutes: 45).qualifies(now: now, minutes: 20))
    }

    @Test func aClaudeIdleNotLongEnoughStaysAwake() {
        #expect(!idle(minutes: 19.9).qualifies(now: now, minutes: 20))
    }

    @Test func zeroMinutesIsNever() {
        #expect(!idle(minutes: 600).qualifies(now: now, minutes: 0))
    }

    @Test func onlyClaudeSleeps() {
        var codex = idle(minutes: 60)
        codex.agent = .codex
        #expect(!codex.qualifies(now: now, minutes: 20))
        var none = idle(minutes: 60)
        none.agent = nil
        #expect(!none.qualifies(now: now, minutes: 20))
    }

    @Test func noIdleSeenStaysAwake() {
        #expect(!SleepCandidate(agent: .claude).qualifies(now: now, minutes: 20))
    }

    @Test(arguments: [
        \SleepCandidate.working, \.asking, \.tasks, \.keptAwake, \.guardWaiting, \.focused, \.onPhone,
        \.deliveryWaiting,
    ])
    func anythingUnderWayOrWaitingKeepsItAwake(_ blocker: WritableKeyPath<SleepCandidate, Bool>) {
        var candidate = idle(minutes: 60)
        candidate[keyPath: blocker] = true
        #expect(!candidate.qualifies(now: now, minutes: 20))
    }
}

@MainActor
struct PaneSleepTests {
    final class Terminals {
        var exits: [UUID] = []
        var resumes: [String] = []
        var exitWorks = true
        var atShell = true
        var pending: [@MainActor () -> Void] = []
    }

    let terminals = Terminals()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pane-sleep-\(UUID().uuidString)/sleeping.json")
    let agent = SleepingAgent(
        pane: UUID(), sessionId: "0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6", name: "wt-17-4c",
        tmux: "lostty-3", folder: "/Users/me/My Repo")

    func makeSleep() -> PaneSleep {
        let terminals = self.terminals
        return PaneSleep(url: url, hands: PaneSleep.Hands(
            exit: { pane in
                terminals.exits.append(pane)
                return terminals.exitWorks
            },
            resume: { agent in
                guard terminals.atShell else { return false }
                terminals.resumes.append(agent.resumeCommand)
                return true
            },
            schedule: { _, work in terminals.pending.append(work) }))
    }

    func saved() throws -> [SleepingAgent] {
        try JSONDecoder().decode([SleepingAgent].self, from: Data(contentsOf: url))
    }

    @Test func fallingAsleepTypesExitAndVeilsThePane() {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        #expect(terminals.exits == [agent.pane])
        #expect(sleep.phase(agent.pane) == .fallingAsleep(agent))
        #expect(sleep.isVeiled(agent.pane))
    }

    @Test func aPaneThatCantTakeExitStaysAwake() {
        terminals.exitWorks = false
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        #expect(sleep.phase(agent.pane) == nil)
        #expect(!sleep.isVeiled(agent.pane))
    }

    @Test func theExitThatSleepAskedForKeepsTheConversation() {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        #expect(sleep.exited(agent.pane))
        #expect(sleep.phase(agent.pane) == .asleep(agent))
        // The shell's command-finished report follows the hook's exit.
        #expect(sleep.exited(agent.pane))
        #expect(sleep.phase(agent.pane) == .asleep(agent))
    }

    @Test func anExitOfAnAwakePaneIsARealExit() {
        #expect(!makeSleep().exited(UUID()))
    }

    @Test func claudeThatNeverExitsIsAwakeAgainAfterTheTimeout() {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        terminals.pending.forEach { $0() }
        #expect(sleep.phase(agent.pane) == nil)
    }

    @Test func theTimeoutLeavesAPaneThatFellAsleep() {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        _ = sleep.exited(agent.pane)
        terminals.pending.forEach { $0() }
        #expect(sleep.phase(agent.pane) == .asleep(agent))
    }

    @Test func wakingResumesTheConversationUnderItsNameAndLiftsTheVeil() {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        _ = sleep.exited(agent.pane)
        sleep.wake(agent.pane)
        #expect(terminals.resumes == [
            "cd '/Users/me/My Repo' && claude --resume 0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6 --name wt-17-4c",
        ])
        #expect(sleep.phase(agent.pane) == .waking(agent))
        #expect(!sleep.isVeiled(agent.pane))
        sleep.started(agent.pane)
        #expect(sleep.phase(agent.pane) == nil)
    }

    @Test func aClaudeThatNeverStartsIsAwakeAfterTheWakeTimeout() {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        _ = sleep.exited(agent.pane)
        terminals.pending.removeAll()
        sleep.wake(agent.pane)
        terminals.pending.forEach { $0() }
        #expect(sleep.phase(agent.pane) == nil)
    }

    @Test func wakingComesBackOnTheModelItWasOn() {
        var agent = self.agent
        agent.model = "claude-fable-5-2"
        #expect(agent.resumeCommand
            == "cd '/Users/me/My Repo' && claude --resume 0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6 --name wt-17-4c --model claude-fable-5-2")
    }

    @Test func wakingTwiceResumesOnce() {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        _ = sleep.exited(agent.pane)
        sleep.wake(agent.pane)
        sleep.wake(agent.pane)
        #expect(terminals.resumes.count == 1)
    }

    @Test func wakingAPaneNotAtItsShellTypesNothingAndLeavesItAwake() {
        terminals.atShell = false
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        _ = sleep.exited(agent.pane)
        sleep.wake(agent.pane)
        #expect(terminals.resumes.isEmpty)
        #expect(sleep.phase(agent.pane) == nil)
    }

    @Test func wakingAPaneStillFallingAsleepWaitsForTheExit() {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        sleep.wake(agent.pane)
        #expect(terminals.resumes.isEmpty)
        #expect(sleep.phase(agent.pane) == .fallingAsleep(agent))
    }

    @Test func aResumedClaudeQuittingBeforeItStartedIsARealExit() {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        _ = sleep.exited(agent.pane)
        sleep.wake(agent.pane)
        #expect(!sleep.exited(agent.pane))
        #expect(sleep.phase(agent.pane) == nil)
    }

    @Test func sleepingPanesAreSavedAndComeBackAsleep() throws {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        #expect(try saved() == [agent])
        _ = sleep.exited(agent.pane)
        #expect(try saved() == [agent])
        #expect(makeSleep().phase(agent.pane) == .asleep(agent))
    }

    @Test func aWakingPaneIsNoLongerSaved() throws {
        let sleep = makeSleep()
        sleep.fallAsleep(agent)
        _ = sleep.exited(agent.pane)
        sleep.wake(agent.pane)
        #expect(try saved().isEmpty)
    }

    @Test func closedAndGonePanesLoseTheirSleep() throws {
        let sleep = makeSleep()
        let other = SleepingAgent(pane: UUID(), sessionId: agent.sessionId, name: "b", tmux: "lostty-4", folder: "/")
        sleep.fallAsleep(agent)
        sleep.fallAsleep(other)
        sleep.closed(agent.pane)
        #expect(sleep.phase(agent.pane) == nil)
        sleep.keep([])
        #expect(sleep.phase(other.pane) == nil)
        #expect(try saved().isEmpty)
    }
}

struct SleepWakeMessageTests {
    let pane = UUID(uuidString: "0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6")!

    @Test func aHeldMessageNamesTheSleeperTheSenderAndTheText() {
        let value = #"{"v":1,"state":"tool","action":"SendMessage","#
            + #""wake":{"pane":"0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6","from":"wt-2","message":"hi"}}"#
        #expect(ClaudeMessage.wake(value) == .init(pane: pane, from: "wt-2", message: "hi"))
    }

    @Test func aMessageTooLongToCarryStillWakes() {
        let value = #"{"v":1,"state":"tool","action":"SendMessage","wake":{"pane":"0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6"}}"#
        #expect(ClaudeMessage.wake(value) == .init(pane: pane, from: nil, message: nil))
    }

    @Test func anythingElseIsNoWake() {
        #expect(ClaudeMessage.wake(#"{"v":1,"state":"tool","action":"SendMessage","denied":"x"}"#) == nil)
        #expect(ClaudeMessage.wake(#"{"v":1,"state":"tool","wake":{"pane":"not-a-uuid"}}"#) == nil)
        #expect(ClaudeMessage.wake(#"{"v":1,"state":"idle","wake":{"pane":"0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6"}}"#) == nil)
    }
}

@MainActor
struct ClaudeRuntimeIdleTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_000) }
    let clock = Clock()
    let pane = UUID()

    func makeRuntime() -> ClaudeRuntime {
        let clock = self.clock
        return ClaudeRuntime(now: { clock.now }, schedule: { _, _ in })
    }

    @Test func aTurnsEndStartsTheIdleClockAndAPromptStopsIt() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        #expect(runtime.idleSince(pane) == nil)
        runtime.apply(.idle, to: pane)
        #expect(runtime.idleSince(pane) == clock.now)
        runtime.apply(.busy, to: pane)
        #expect(runtime.idleSince(pane) == nil)
    }

    @Test func aPermissionQuestionIsNotIdle() {
        let runtime = makeRuntime()
        runtime.apply(.busy, to: pane)
        runtime.apply(.idle, to: pane, permission: true)
        #expect(runtime.idleSince(pane) == nil)
    }

    @Test func aKeyTypedRestartsTheIdleClock() {
        let runtime = makeRuntime()
        runtime.apply(.idle, to: pane)
        clock.now = clock.now.addingTimeInterval(600)
        runtime.keyTyped(pane)
        #expect(runtime.idleSince(pane) == clock.now)
    }

    @Test func foundIdleCountsFromNowOnlyWhenNothingIsKnown() {
        let runtime = makeRuntime()
        runtime.foundIdle(pane)
        let first = clock.now
        clock.now = clock.now.addingTimeInterval(60)
        runtime.foundIdle(pane)
        #expect(runtime.idleSince(pane) == first)
        runtime.apply(.busy, to: pane)
        runtime.foundIdle(pane)
        #expect(runtime.idleSince(pane) == nil)
    }

    @Test func aStopWithScheduledWorkHoldsItUntilAStopWithout() {
        let runtime = makeRuntime()
        let stop = { (pending: Bool) in #"{"v":1,"state":"idle","pending":\#(pending)}"# }
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: stop(true))
        #expect(runtime.pendingWork.contains(pane))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: #"{"v":1,"state":"idle","permission":true}"#)
        #expect(runtime.pendingWork.contains(pane))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: stop(false))
        #expect(!runtime.pendingWork.contains(pane))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: stop(true))
        runtime.userVarChanged(pane, name: "LOSTTY_CLAUDE", value: #"{"v":1,"state":"exit"}"#)
        #expect(!runtime.pendingWork.contains(pane))
    }
}
#endif
