#if os(macOS)
import Foundation
import Testing
@testable import Lostty

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

    @Test func aPersistentBubbleStaysUntilDismissed() {
        let center = make()
        var n = note(.update)
        n.persistent = true
        center.post(n)
        center.markShown(n.id)
        center.setHovering(n.id, true)
        center.setHovering(n.id, false)
        #expect(harness.pending.isEmpty)
        center.dismiss(kind: .update)
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
        let n = HookNotifications.missing(.codex, coordination: false)
        #expect(n.kind == .hooksMissing(.codex))
        #expect(n.title == "Codex isn't connected")
        #expect(n.detail == "Lostty can't show the trace or Ready for response for Codex.")
        #expect(HookNotifications.missing(.claude, coordination: false).detail
            == "Lostty can't show the trace, Ready for response or usage for Claude.")
        #expect(n.actionTitle == "Connect")
    }

    @Test func withCoordinationOnTheMissingBubbleNamesTheGuard() {
        let n = HookNotifications.missing(.codex, coordination: true)
        #expect(n.detail.contains("Lostty's guard and trace aren't set up for Codex"))
        #expect(HookNotifications.missing(.claude, coordination: true).detail.contains("Lostty's guard and trace aren't set up for Claude"))
    }

    @Test func connectedBubbleSaysToRestart() {
        let claude = HookNotifications.result(.claude, exitCode: 0, stderr: "", coordination: false)
        #expect(claude.title == "Claude connected")
        #expect(claude.detail == "Restart any running Claude sessions to see the trace and usage.")
        #expect(claude.actionTitle == nil)
        let codex = HookNotifications.result(.codex, exitCode: 0, stderr: "", coordination: false)
        #expect(codex.detail == "Restart any running Codex sessions to see the trace. Codex asks you to approve Lostty's hooks once.")
        #expect(!codex.detail.contains("guard"))
    }

    @Test func withCoordinationOnTheConnectedBubbleNamesTheGuard() {
        let claude = HookNotifications.result(.claude, exitCode: 0, stderr: "", coordination: true)
        #expect(claude.detail.contains("guard"))
        #expect(claude.detail.contains("Restart"))
        #expect(!claude.detail.contains(HookNotifications.codexTrustMessage))
        let codex = HookNotifications.result(.codex, exitCode: 0, stderr: "", codexTrusted: false, coordination: true)
        #expect(codex.detail.contains(HookNotifications.codexTrustMessage))
        let trusted = HookNotifications.result(.codex, exitCode: 0, stderr: "", codexTrusted: true, coordination: true)
        #expect(!trusted.detail.contains(HookNotifications.codexTrustMessage))
    }

    @Test func codexHookTrustIsFoundInItsConfig() {
        let table = """
        model = "gpt-5"

        [hooks.state."/Users/me/.codex/hooks.json:pre_tool_use:0"]
        trusted_hash = "abc123"
        """
        #expect(HookNotifications.codexTrustsGuard(configToml: table, home: "/Users/me"))
        let inline = """
        [hooks.state]
        "/Users/me/.codex/hooks.json:pre_tool_use:0" = { trusted_hash = "abc" }
        """
        #expect(HookNotifications.codexTrustsGuard(configToml: inline, home: "/Users/me"))
        // Only the stop hook trusted, or the guard's table without a hash.
        let other = """
        [hooks.state."/Users/me/.codex/hooks.json:stop:0"]
        trusted_hash = "abc"

        [hooks.state."/Users/me/.codex/hooks.json:pre_tool_use:0"]
        enabled = true

        [profiles.x]
        trusted_hash = "zzz"
        """
        #expect(!HookNotifications.codexTrustsGuard(configToml: other, home: "/Users/me"))
        #expect(!HookNotifications.codexTrustsGuard(configToml: "", home: "/Users/me"))
        // A project's hooks.json, or another user's, isn't the user's own.
        let project = """
        [hooks.state."/Users/me/work/app/.codex/hooks.json:pre_tool_use:0"]
        trusted_hash = "abc"

        [hooks.state."/Users/other/.codex/hooks.json:pre_tool_use:0"]
        trusted_hash = "abc"
        """
        #expect(!HookNotifications.codexTrustsGuard(configToml: project, home: "/Users/me"))
        let projectInline = """
        [hooks.state]
        "/Users/me/work/.codex/hooks.json:pre_tool_use:0" = { trusted_hash = "abc" }
        """
        #expect(!HookNotifications.codexTrustsGuard(configToml: projectInline, home: "/Users/me"))
    }

    @Test func failedConnectShowsTheReason() {
        let n = HookNotifications.result(.claude, exitCode: 1, stderr: "claude-hooks: claude: cannot write x (AccessDenied); left untouched\n")
        #expect(n.title == "Couldn't connect Claude")
        #expect(n.detail.contains("AccessDenied"))
    }
}
#endif
