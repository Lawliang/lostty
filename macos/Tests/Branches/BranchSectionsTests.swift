#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct BranchSectionsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func branch(_ name: String, daysAgo: Double) -> BranchInfo {
        BranchInfo(name: name, tip: name + "-sha", lastCommit: now.addingTimeInterval(-daysAgo * 24 * 3600),
                   subject: "s", upstream: .none, vsBase: nil)
    }

    private func snapshot(_ branches: [BranchInfo], worktrees: [Worktree] = [], base: String? = "main") -> RepoSnapshot {
        RepoSnapshot(root: "/r", commonDir: "/r/.git", base: base, branches: branches, worktrees: worktrees)
    }

    @Test func activeFirstThenRecentThenOlder() {
        let s = BranchSession(origin: .pane(UUID()), title: "p", pwd: "/r", agent: .working)
        let snap = snapshot([branch("main", daysAgo: 1), branch("feat", daysAgo: 2), branch("stale", daysAgo: 45),
                             branch("new", daysAgo: 0.5)])
        let sections = BranchSections.build(snap, placement: Placement(byBranch: ["feat": [s]], detached: []), now: now)
        #expect(sections.active.map(\.id) == ["feat"])
        #expect(sections.active[0].sessions == [s])
        #expect(sections.recent.map(\.id) == ["new", "main"])
        #expect(sections.older.map(\.id) == ["stale"])
    }

    @Test func theBaseIsNeverOlder() {
        let sections = BranchSections.build(snapshot([branch("main", daysAgo: 90)]), placement: Placement(), now: now)
        #expect(sections.recent.map(\.id) == ["main"])
        #expect(sections.recent[0].isBase)
    }

    @Test func thirtyDaysIsStillRecent() {
        let sections = BranchSections.build(
            snapshot([branch("edge", daysAgo: 30), branch("past", daysAgo: 30.01)], base: nil),
            placement: Placement(), now: now)
        #expect(sections.recent.map(\.id) == ["edge"])
        #expect(sections.older.map(\.id) == ["past"])
    }

    @Test func marksRebasingAndLinkedWorktrees() {
        let trees = [
            Worktree(path: "/r", head: "1", branch: "main", rebasing: nil, isMain: true),
            Worktree(path: "/wt/feat", head: "2", branch: "feat", rebasing: nil, isMain: false),
            Worktree(path: "/wt/reb", head: "3", branch: nil, rebasing: "fix", isMain: false),
        ]
        let sections = BranchSections.build(
            snapshot([branch("main", daysAgo: 1), branch("feat", daysAgo: 1), branch("fix", daysAgo: 1)], worktrees: trees),
            placement: Placement(), now: now)
        let rows = Dictionary(uniqueKeysWithValues: sections.recent.map { ($0.id, $0) })
        #expect(rows["main"]?.worktreePath == nil)
        #expect(rows["feat"]?.worktreePath == "/wt/feat")
        #expect(rows["fix"]?.isRebasing == true)
    }

    @Test func carriesDetachedGroups() {
        let group = DetachedGroup(sha: "abc1234", sessions: [])
        let sections = BranchSections.build(snapshot([]), placement: Placement(byBranch: [:], detached: [group]), now: now)
        #expect(sections.detached == [group])
    }
}
#endif
