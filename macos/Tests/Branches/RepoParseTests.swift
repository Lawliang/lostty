#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct RepoParseTests {
    @Test func parsesBranchLines() {
        let output = """
        main\taaa111\t1791839107\torigin/main\t\tfirst commit
        feat/x\tbbb222\t1791838956\torigin/feat/x\t[ahead 1, behind 2]\tsubject\twith a tab
        local\tccc333\t1791437387\t\t\tno upstream

        """
        let branches = RepoParse.branches(output)
        #expect(branches.count == 3)
        #expect(branches[0] == BranchInfo(
            name: "main", tip: "aaa111", lastCommit: Date(timeIntervalSince1970: 1791839107),
            subject: "first commit", upstream: .tracking(name: "origin/main", ahead: 0, behind: 0), vsBase: nil))
        #expect(branches[1].name == "feat/x")
        #expect(branches[1].subject == "subject\twith a tab")
        #expect(branches[1].upstream == .tracking(name: "origin/feat/x", ahead: 1, behind: 2))
        #expect(branches[2].upstream == .none)
    }

    @Test func skipsMalformedBranchLines() {
        #expect(RepoParse.branches("garbage\nmain\tsha\tnot-a-date\t\t\tx\n").isEmpty)
    }

    @Test func parsesUpstreamTracking() {
        #expect(RepoParse.upstream(name: "", track: "") == .none)
        #expect(RepoParse.upstream(name: "origin/a", track: "") == .tracking(name: "origin/a", ahead: 0, behind: 0))
        #expect(RepoParse.upstream(name: "origin/a", track: "[ahead 3]") == .tracking(name: "origin/a", ahead: 3, behind: 0))
        #expect(RepoParse.upstream(name: "origin/a", track: "[behind 4]") == .tracking(name: "origin/a", ahead: 0, behind: 4))
        #expect(RepoParse.upstream(name: "origin/a", track: "[gone]") == .gone(name: "origin/a"))
    }

    @Test func parsesWorktrees() {
        let porcelain = """
        worktree /r/main
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /r/wt
        HEAD 2222222222222222222222222222222222222222
        branch refs/heads/feature/a

        worktree /r/det
        HEAD 3333333333333333333333333333333333333333
        detached

        """
        let trees = RepoParse.worktrees(porcelain)
        #expect(trees == [
            Worktree(path: "/r/main", head: "1111111111111111111111111111111111111111", branch: "main", rebasing: nil, isMain: true),
            Worktree(path: "/r/wt", head: "2222222222222222222222222222222222222222", branch: "feature/a", rebasing: nil, isMain: false),
            Worktree(path: "/r/det", head: "3333333333333333333333333333333333333333", branch: nil, rebasing: nil, isMain: false),
        ])
    }

    @Test func skipsBareAndPrunableWorktrees() {
        let porcelain = """
        worktree /r/bare.git
        bare

        worktree /r/gone
        HEAD 4444444444444444444444444444444444444444
        branch refs/heads/old
        prunable gitdir file points to non-existent location

        worktree /r/live
        HEAD 5555555555555555555555555555555555555555
        branch refs/heads/live

        """
        let trees = RepoParse.worktrees(porcelain)
        #expect(trees.map(\.path) == ["/r/live"])
        #expect(trees[0].isMain == false)
    }

    @Test func theRepoRootIsTheFirstEntryEvenWhenBare() {
        #expect(RepoParse.repoRoot("worktree /r/main\nHEAD 1111\nbranch refs/heads/main\n\nworktree /r/wt\nHEAD 2222\ndetached\n") == "/r/main")
        #expect(RepoParse.repoRoot("worktree /r/bare.git\nbare\n\nworktree /r/live\nHEAD 5555\nbranch refs/heads/live\n") == "/r/bare.git")
        #expect(RepoParse.repoRoot("") == nil)
    }

    @Test func parsesAheadBehindAsBehindThenAhead() {
        #expect(RepoParse.aheadBehind("3\t5\n") == AheadBehind(ahead: 5, behind: 3))
        #expect(RepoParse.aheadBehind("") == nil)
    }

    @Test func parsesRebaseHeadName() {
        #expect(RepoParse.rebaseHead("refs/heads/feat/x\n") == "feat/x")
        #expect(RepoParse.rebaseHead("detached HEAD\n") == nil)
    }

    @Test func countsLines() {
        #expect(RepoParse.lineCount("") == 0)
        #expect(RepoParse.lineCount("a\nb\n") == 2)
    }

    @Test func snapshotNameIsTheRootFolder() {
        let snapshot = RepoSnapshot(root: "/x/lostty", commonDir: "/x/lostty/.git", base: nil, branches: [], worktrees: [])
        #expect(snapshot.name == "lostty")
    }
}
#endif
