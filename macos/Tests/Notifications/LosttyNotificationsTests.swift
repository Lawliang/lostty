#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct LosttyNotificationsTests {
    final class Harness {
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    }

    let harness = Harness()

    func make() -> LosttyNotifications {
        let harness = self.harness
        return LosttyNotifications(schedule: { delay, work in harness.pending.append((delay, work)) })
    }

    func runPending() {
        let work = harness.pending
        harness.pending = []
        for item in work { item.work() }
    }

    func note(_ kind: LosttyNotification.Kind) -> LosttyNotification {
        LosttyNotification(kind: kind, title: "Title", detail: "Detail")
    }

    @Test func postAndDismiss() {
        let center = make()
        let n = note(.hooksMissing(.claude))
        center.post(n)
        #expect(center.items.map(\.id) == [n.id])
        center.dismiss(n.id)
        #expect(center.items.isEmpty)
    }

    @Test func fadesEightSecondsAfterItIsFirstShown() {
        let center = make()
        let n = note(.hooksMissing(.claude))
        center.post(n)
        // Not shown in any window yet: no countdown.
        #expect(harness.pending.isEmpty)
        center.markShown(n.id)
        center.markShown(n.id)
        #expect(harness.pending.count == 1)
        #expect(harness.pending[0].delay == LosttyNotifications.lifetime)
        #expect(LosttyNotifications.lifetime == 8)
        runPending()
        #expect(center.items.isEmpty)
    }

    @Test func hoveringKeepsItAndLeavingRestartsTheCountdown() {
        let center = make()
        let n = note(.hooksMissing(.codex))
        center.post(n)
        center.markShown(n.id)
        center.setHovering(n.id, true)
        runPending()
        #expect(center.items.count == 1)
        center.setHovering(n.id, false)
        #expect(harness.pending.count == 1)
        runPending()
        #expect(center.items.isEmpty)
    }

    @Test func postingTheSameKindReplacesIt() {
        let center = make()
        center.post(note(.hooksMissing(.claude)))
        let second = note(.hooksMissing(.claude))
        center.post(second)
        center.post(note(.hooksMissing(.codex)))
        #expect(center.items.count == 2)
        #expect(center.items.first?.id == second.id)
    }

    @Test func aConnectResultReplacesItsAgentsBubble() {
        let center = make()
        center.post(note(.hooksMissing(.claude)))
        center.post(note(.hooks(.claude)))
        #expect(center.items.count == 1)
        #expect(center.items.first?.kind == .hooks(.claude))
    }
}

struct HookNotificationsTests {
    @Test func onlyInstalledAgentsWithoutHooksGetABubble() {
        let missing = HookNotifications.missingAgents(
            installed: [.claude, .codex],
            status: { $0 == .claude ? .notInstalled : .installed })
        #expect(missing == [.claude])
    }

    @Test func outdatedHooksCountAsMissing() {
        #expect(HookNotifications.missingAgents(installed: [.codex], status: { _ in .partial }) == [.codex])
    }

    @Test func agentsThatAreNotInstalledGetNoBubble() {
        #expect(HookNotifications.missingAgents(installed: [], status: { _ in .notInstalled }).isEmpty)
    }

    @Test func unreadableOrUnknownStatusGetsNoBubble() {
        // Connect could not fix an unreadable file; the menu reports it instead.
        #expect(HookNotifications.missingAgents(installed: [.claude], status: { _ in .unreadable }).isEmpty)
        #expect(HookNotifications.missingAgents(installed: [.claude], status: { _ in nil }).isEmpty)
    }

    @Test func missingBubbleNamesTheAgentAndOffersConnect() {
        let n = HookNotifications.missing(.codex)
        #expect(n.kind == .hooksMissing(.codex))
        #expect(n.title == "Codex isn't connected")
        #expect(n.actionTitle == "Connect")
    }

    @Test func connectedBubbleSaysToRestart() {
        let claude = HookNotifications.result(.claude, exitCode: 0, stderr: "")
        #expect(claude.title == "Claude connected")
        #expect(claude.detail.contains("Restart"))
        #expect(claude.actionTitle == nil)
        let codex = HookNotifications.result(.codex, exitCode: 0, stderr: "")
        #expect(codex.detail.contains("approve"))
    }

    @Test func failedConnectShowsTheReason() {
        let n = HookNotifications.result(.claude, exitCode: 1, stderr: "claude-hooks: claude: cannot write x (AccessDenied); left untouched\n")
        #expect(n.title == "Couldn't connect Claude")
        #expect(n.detail.contains("AccessDenied"))
    }
}
#endif
