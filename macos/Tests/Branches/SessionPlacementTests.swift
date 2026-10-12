#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SessionPlacementTests {
    private func session(_ pwd: String, _ title: String = "pane") -> BranchSession {
        BranchSession(origin: .pane(UUID()), title: title, pwd: pwd, agent: nil)
    }

    private let trees = [
        Worktree(path: "/r/repo", head: "aaaaaaa111", branch: "main", rebasing: nil, isMain: true),
        Worktree(path: "/r/repo/.claude/worktrees/ui", head: "bbbbbbb222", branch: "ui", rebasing: nil, isMain: false),
        Worktree(path: "/r/det", head: "ccccccc333", branch: nil, rebasing: nil, isMain: false),
        Worktree(path: "/r/reb", head: "ddddddd444", branch: nil, rebasing: "feat", isMain: false),
    ]

    @Test func placesSessionsByTheirWorktreesBranch() {
        let a = session("/r/repo/src")
        let b = session("/r/repo")
        let placement = SessionPlacement.assign([a, b], worktrees: trees)
        #expect(placement.byBranch["main"] == [a, b])
    }

    @Test func aNestedWorktreeWinsOverItsParent() {
        let s = session("/r/repo/.claude/worktrees/ui/macos")
        #expect(SessionPlacement.assign([s], worktrees: trees).byBranch["ui"] == [s])
    }

    @Test func matchesPathsCaseInsensitivelyOnComponentBoundaries() {
        let upper = session("/R/Repo/src")
        let sibling = session("/r/repo-other")
        let placement = SessionPlacement.assign([upper, sibling], worktrees: trees)
        #expect(placement.byBranch["main"] == [upper])
        #expect(placement.byBranch.values.flatMap { $0 }.contains(sibling) == false)
    }

    @Test func detachedSessionsGroupByShortSha() {
        let s = session("/r/det")
        let placement = SessionPlacement.assign([s], worktrees: trees)
        #expect(placement.detached == [DetachedGroup(sha: "ccccccc", sessions: [s])])
        #expect(placement.byBranch.isEmpty)
    }

    @Test func aRebasingSessionSitsUnderTheBranchBeingRebased() {
        let s = session("/r/reb")
        #expect(SessionPlacement.assign([s], worktrees: trees).byBranch["feat"] == [s])
    }

    @Test func followsSymlinkedDirectories() throws {
        let dir = try TempRepo.makeDirectory()
        try FileManager.default.createDirectory(atPath: dir + "/real", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dir + "/link", withDestinationPath: dir + "/real")
        let tree = Worktree(path: dir + "/real", head: "eeeeeee", branch: "main", rebasing: nil, isMain: true)
        let s = session(dir + "/link")
        #expect(SessionPlacement.assign([s], worktrees: [tree]).byBranch["main"] == [s])
    }
}
#endif
