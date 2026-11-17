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
        return LosttyNotifications(muted: { false }, schedule: { delay, work in harness.pending.append((delay, work)) })
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

    @Test func fadesSixSecondsAfterItIsFirstShown() {
        let center = make()
        let n = note(.hooksMissing(.claude))
        center.post(n)
        // Not shown in any window yet: no countdown.
        #expect(harness.pending.isEmpty)
        center.markShown(n.id)
        center.markShown(n.id)
        #expect(harness.pending.count == 1)
        #expect(harness.pending[0].delay == LosttyNotifications.lifetime)
        #expect(LosttyNotifications.lifetime == 6)
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

    @Test func aBubbleWithAButtonStaysUntilDismissed() {
        let center = make()
        var n = note(.update)
        n.actionTitle = "Restart to Update"
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
        #expect(center.items.last?.id == second.id)
    }

    @Test func theNewestIsOnTop() {
        let center = make()
        let first = note(.update), second = note(.zoneLeft("Textberry"))
        center.post(first)
        center.post(second)
        #expect(center.items.map(\.id) == [second.id, first.id])
        // A replacement goes on top too.
        let again = note(.update)
        center.post(again)
        #expect(center.items.map(\.id) == [again.id, second.id])
    }

    @Test func aGroupedBubbleIsFoundToAddTo() {
        let center = make()
        var n = note(.zoneLeft("Lostty"))
        n.group = ["a"]
        center.post(n)
        #expect(center.current(.zoneLeft("Lostty"))?.group == ["a"])
        #expect(center.current(.zoneLeft("Other")) == nil)
    }

    @Test func eachZoneStacksAndTheRestStandAlone() {
        let zoneA = UUID(), zoneB = UUID()
        let start = Date()
        func bubble(_ kind: LosttyNotification.Kind, _ zone: UUID?, _ at: TimeInterval) -> LosttyNotification {
            var n = note(kind)
            n.zone = zone
            n.posted = start.addingTimeInterval(at)
            return n
        }
        let left = bubble(.zoneLeft("A"), zoneA, 1)
        let update = bubble(.update, nil, 2)
        let kept = bubble(.keptInside(pane: UUID()), zoneB, 3)
        let hooks = bubble(.hooksMissing(.claude), nil, 4)
        let ready = TerminalNotice(
            pane: UUID(), title: "Fix", project: nil, recap: RequestRecap(), zone: zoneA, posted: start.addingTimeInterval(5))
        let groups = NotificationGroup.make([hooks, kept, update, left], [ready])
        // Newest first; zone A's stack holds both kinds, newest on top.
        #expect(groups.map(\.zone) == [zoneA, nil, zoneB, nil])
        #expect(groups[0].entries.map(\.id) == [ready.id, left.id])
        #expect(groups[1].entries.map(\.id) == [hooks.id])
        #expect(groups[2].entries.map(\.id) == [kept.id])
        #expect(groups[3].entries.map(\.id) == [update.id])
    }

    @Test func onlyTheLastKeyWindowShowsTheBubbles() {
        let center = make()
        // Kept alive, so the two can't share an address.
        let windows = (NSObject(), NSObject())
        let a = ObjectIdentifier(windows.0), b = ObjectIdentifier(windows.1)
        center.show(in: a)
        center.show(in: b)
        #expect(center.front == b)
        center.windowClosed(a)
        #expect(center.front == b)
        center.windowClosed(b)
        #expect(center.front == nil)
    }

    @Test func theAgeReadsLikeIOS() {
        let now = Date()
        #expect(LosttyNotification.age(of: now.addingTimeInterval(-20), now: now) == "now")
        #expect(LosttyNotification.age(of: now.addingTimeInterval(-245), now: now) == "4m ago")
        #expect(LosttyNotification.age(of: now.addingTimeInterval(-7300), now: now) == "2h ago")
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
        #expect(n.detail == "Connect it to see the trace and Ready for response.")
        #expect(HookNotifications.missing(.claude, coordination: false).detail
            == "Connect it to see the trace, Ready for response and usage.")
        #expect(n.actionTitle == "Connect")
        #expect(n.stays)
    }

    @Test func withCoordinationOnTheMissingBubbleSaysRiskyActionsAreChecked() {
        let n = HookNotifications.missing(.codex, coordination: true)
        #expect(n.detail == "Connect it so Lostty can check its risky actions and show the trace and Ready for response.")
        #expect(!n.detail.contains("guard"))
    }

    @Test func clickingAClaudeBubbleOpensClaudeIntegration() {
        #expect(HookNotifications.missing(.claude, coordination: false).open != nil)
        #expect(HookNotifications.missing(.codex, coordination: false).open == nil)
    }

    @Test func connectedBubbleSaysToRestart() {
        let claude = HookNotifications.result(.claude, exitCode: 0, stderr: "", coordination: false)
        #expect(claude.title == "Claude connected")
        #expect(claude.detail == "Restart running Claude sessions to pick it up.")
        #expect(claude.actionTitle == nil)
        #expect(!claude.stays)
        let codex = HookNotifications.result(.codex, exitCode: 0, stderr: "", coordination: false)
        #expect(codex.detail == "Restart running Codex sessions, then approve Lostty's hooks in Codex once.")
    }

    @Test func withCoordinationOnCodexIsAskedToApproveOnlyUntilItTrustsTheHooks() {
        let claude = HookNotifications.result(.claude, exitCode: 0, stderr: "", coordination: true)
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
        #expect(n.detail == "claude-hooks: claude: cannot write x (AccessDenied); left untouched")
    }
}
#endif
