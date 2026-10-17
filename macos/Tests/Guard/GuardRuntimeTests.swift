#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct GuardRuntimeTests {
    final class Log {
        var posted: [Int] = []
        var withdrawn: [Int] = []
        var typed: [(UUID, String)] = []
        var paneAlive = true
        var saves = 0
        var now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    }

    func make(_ log: Log) -> GuardRuntime {
        GuardRuntime(effects: .init(
            post: { log.posted.append($0.id) },
            withdraw: { log.withdrawn.append($0) },
            type: { pane, text in
                guard log.paneAlive else { return false }
                log.typed.append((pane, text))
                return true
            },
            save: { _ in log.saves += 1 },
            now: { log.now }
        ))
    }

    let pane = UUID()

    func check(_ input: String = "git push") -> GuardCheck {
        GuardCheck(v: 1, pane: pane.uuidString, agent: "claude", session: nil, tool: "Bash", input: input,
                   cwd: "/r", repo: nil, branch: nil, group: "leaving", why: "w", lost: nil, reason: nil)
    }

    @Test func aNewRequestIsPostedOnceAndTheAgentPaneIsRemembered() {
        let log = Log()
        let rt = make(log)
        #expect(rt.handle(check()) == .deny(1))
        #expect(rt.handle(check()) == .deny(1))
        #expect(log.posted == [1])
        #expect(rt.agentPanes[pane] == "claude")
        #expect(rt.pending(for: pane)?.id == 1)
    }

    @Test func approvingTypesTheOutcomeAndLetsTheRetryThrough() {
        let log = Log()
        let rt = make(log)
        _ = rt.handle(check())
        rt.approve(1)
        #expect(log.withdrawn == [1])
        #expect(log.typed.count == 1)
        #expect(log.typed.first?.1 == GuardRuntime.outcomeText(1, approved: true))
        #expect(rt.handle(check()) == .allow)
    }

    @Test func denyingTypesTheOutcome() {
        let log = Log()
        let rt = make(log)
        _ = rt.handle(check())
        rt.deny(1)
        #expect(log.typed.first?.1 == GuardRuntime.outcomeText(1, approved: false))
        #expect(rt.handle(check()) == .deny(2))
    }

    @Test func nothingIsTypedOnceTheAgentHasGone() {
        let log = Log()
        let rt = make(log)
        _ = rt.handle(check())
        rt.agentGone(pane)
        rt.approve(1)
        #expect(log.typed.isEmpty)
        // The approval still holds for a retry within 10 minutes.
        #expect(rt.handle(check()) == .allow)
    }

    @Test func theTimerSavesNothingWhenNothingLapsed() {
        let log = Log()
        let rt = make(log)
        _ = rt.handle(check())
        let before = log.saves
        rt.tick()
        #expect(log.saves == before)
        #expect(log.withdrawn.isEmpty)
    }

    @Test func aLapsedRequestIsWithdrawnAndSaved() {
        let log = Log()
        let rt = make(log)
        _ = rt.handle(check())
        let before = log.saves
        log.now = log.now.addingTimeInterval(3601 + 60)
        rt.tick()
        #expect(log.withdrawn == [1])
        #expect(log.saves == before + 1)
    }

    @Test func outcomeTexts() {
        #expect(GuardRuntime.outcomeText(42, approved: true) == "Approved #42 in Lostty. Run it now, exactly as before.")
        #expect(GuardRuntime.outcomeText(42, approved: false) == "Denied #42 in Lostty. Don't run it, and don't work around it.")
    }

    @Test func statePanesAreAgentPanesAndAKnownKindSticks() {
        let rt = make(Log())
        let other = UUID()
        rt.agentSeen(other, kind: nil)
        #expect(rt.agentPanes[other] == GuardHealth.unknownAgent)
        rt.agentSeen(other, kind: .codex)
        #expect(rt.agentPanes[other] == "codex")
        rt.agentSeen(other, kind: nil)
        #expect(rt.agentPanes[other] == "codex")
        rt.disconnected = [.codex]
        #expect(GuardHealth.showsDisconnected(agent: rt.agentPanes[other], disconnected: rt.disconnected))
        rt.agentGone(other)
        #expect(rt.agentPanes[other] == nil)
    }
}
#endif
