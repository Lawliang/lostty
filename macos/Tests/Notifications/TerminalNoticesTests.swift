#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct TerminalNoticesTests {
    final class Harness {
        var pending: [(delay: TimeInterval, work: @MainActor () -> Void)] = []
    }

    let harness = Harness()
    let p1 = UUID(), p2 = UUID()

    func make() -> TerminalNotices {
        let harness = self.harness
        return TerminalNotices(schedule: { delay, work in harness.pending.append((delay, work)) })
    }

    func runPending() {
        let work = harness.pending
        harness.pending = []
        for item in work { item.work() }
    }

    func notice(_ pane: UUID, _ title: String = "Fix the login") -> TerminalNotice {
        TerminalNotice(pane: pane, title: title, project: nil, recap: RequestRecap())
    }

    @Test func onlyAPaneAwaitingAResponseGetsOneNewestFirstAndEachPaneOnce() {
        let center = make()
        center.post(notice(p1))
        #expect(center.items.isEmpty)
        center.awaitingChanged([p1, p2])
        center.post(notice(p1, "First"))
        center.post(notice(p2))
        center.post(notice(p1, "Second"))
        #expect(center.items.map(\.title) == ["Second", "Fix the login"])
        #expect(center.items.map(\.pane) == [p1, p2])
    }

    @Test func itCollapsesFourSecondsAfterItShowsUnlessHovered() throws {
        let center = make()
        center.awaitingChanged([p1, p2])
        let first = notice(p1), second = notice(p2)
        center.post(first)
        center.post(second)
        #expect(harness.pending.map(\.delay) == [4, 4])
        center.setHovering(second.id, true)
        runPending()
        #expect(center.collapsed == [first.id])
        center.setHovering(second.id, false)
        runPending()
        #expect(center.collapsed == [first.id, second.id])
    }

    @Test func itGoesWhenItsPaneNoLongerAwaits() {
        let center = make()
        center.awaitingChanged([p1, p2])
        let first = notice(p1)
        center.post(first)
        center.post(notice(p2))
        runPending()
        center.awaitingChanged([p2])
        #expect(center.items.map(\.pane) == [p2])
        #expect(!center.collapsed.contains(first.id))
    }

    @Test func theTitleLeavesOutTheAgentsMark() {
        #expect(TerminalNotices.title("✳ Fix the login") == "Fix the login")
        #expect(TerminalNotices.title("◐ Fix the login") == "Fix the login")
        #expect(TerminalNotices.title("zsh") == "zsh")
    }

    @Test func theRecapIsTheLastTypedRequestAndTheReplyAfterIt() {
        func line(_ object: [String: Any]) -> Data {
            (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        }
        func user(_ content: Any, meta: Bool = false) -> Data {
            line(["type": "user", "isMeta": meta, "message": ["role": "user", "content": content]])
        }
        func assistant(_ blocks: [[String: Any]]) -> Data {
            line(["type": "assistant", "message": ["role": "assistant", "content": blocks]])
        }
        let earlier = [user("an older request"), assistant([["type": "text", "text": "Older reply"]])]
        let lines = earlier + [
            user("\n  Track the karaoke mic in the logs\nwith detail"),
            assistant([["type": "text", "text": "Looking."], ["type": "tool_use", "name": "Bash", "input": [:]]]),
            user([["type": "tool_result", "content": "ok"]]),
            user("<task-notification>done</task-notification>"),
            user("Caveat: the messages below…", meta: true),
            assistant([["type": "text", "text": "Added mode and mic logs.\nDetails follow."]]),
        ]
        #expect(RequestRecap.from(lines) == RequestRecap(request: "Track the karaoke mic in the logs", reply: "Added mode and mic logs."))
        #expect(RequestRecap.from(lines + [user("next one")]) == RequestRecap(request: "next one", reply: nil))
        #expect(RequestRecap.from([]) == RequestRecap())
    }
}
#endif
