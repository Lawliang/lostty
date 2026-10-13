#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct RepoReaderTests {
    private let now = Date()
    private var sixtyDaysAgo: Date { now.addingTimeInterval(-60 * 24 * 3600) }

    private func readSnapshot(_ pwd: String) throws -> RepoSnapshot {
        let location = try #require(RepoReader.locate(pwd: pwd))
        return try #require(RepoReader.read(location, now: now))
    }

    /// main (2 commits, the first 60 days old), feat (+2 on main) checked out
    /// in worktree `wt`, old (at the first commit), and a detached worktree `det`.
    private func makeFixture() throws -> (repo: TempRepo, wt: String, det: String) {
        let repo = try TempRepo.make(firstCommit: sixtyDaysAgo)
        try repo.git("branch", "old")
        try repo.commit("second")
        try repo.git("checkout", "-q", "-b", "feat")
        try repo.commit("feat one")
        try repo.commit("feat two")
        try repo.git("checkout", "-q", "main")
        let parent = (repo.root as NSString).deletingLastPathComponent
        let wt = parent + "/wt"
        let det = parent + "/det"
        try repo.git("worktree", "add", "-q", wt, "feat")
        try repo.git("worktree", "add", "-q", "--detach", det, "main")
        return (repo, wt, det)
    }

    @Test func locatesTheMainWorktreeFromALinkedWorktreeSubfolder() throws {
        let (repo, wt, _) = try makeFixture()
        try FileManager.default.createDirectory(atPath: wt + "/sub", withIntermediateDirectories: true)
        let location = try #require(RepoReader.locate(pwd: wt + "/sub"))
        #expect(location.root == repo.root)
        #expect(location.commonDir == repo.root + "/.git")
        #expect(RepoReader.locate(pwd: repo.root) == location)
    }

    @Test func aBareRepoWithLinkedWorktreesIsARepo() throws {
        let source = try TempRepo.make()
        try source.git("branch", "feat")
        let parent = try TempRepo.makeDirectory()
        let bare = TempRepo(root: parent + "/proj.git")
        try FileManager.default.createDirectory(atPath: bare.root, withIntermediateDirectories: true)
        try bare.git("init", "-q", "--bare", "-b", "main")
        try bare.git("fetch", "-q", source.root, "main:main", "feat:feat")
        try bare.git("worktree", "add", "-q", parent + "/main", "main")
        try bare.git("worktree", "add", "-q", parent + "/feat", "feat")

        let location = try #require(RepoReader.locate(pwd: parent + "/feat"))
        #expect(location.root == bare.root)
        #expect(location.commonDir == bare.root)
        #expect(RepoReader.locate(pwd: parent + "/main") == location)

        let snapshot = try #require(RepoReader.read(location, now: now))
        #expect(snapshot.name == "proj.git")
        #expect(snapshot.base == "main")
        #expect(Set(snapshot.branches.map(\.name)) == ["main", "feat"])
        #expect(snapshot.worktrees.map { ProjectResolver.canonical($0.path) }.sorted() == [parent + "/feat", parent + "/main"])
        #expect(snapshot.worktrees.allSatisfy { !$0.isMain })
        let sections = BranchSections.build(snapshot, placement: Placement(), now: now)
        #expect(sections.recent.first { $0.id == "feat" }?.worktreePath.map(ProjectResolver.canonical) == parent + "/feat")
    }

    @Test func outsideARepoIsNil() throws {
        #expect(RepoReader.locate(pwd: try TempRepo.makeDirectory()) == nil)
    }

    @Test func aHomeDirectoryUnderGitIsNotARepo() throws {
        let repo = try TempRepo.make()
        #expect(RepoReader.locate(pwd: repo.root, home: repo.root) == nil)
    }

    @Test func readsBranchesBaseAndWorktrees() throws {
        let (repo, wt, det) = try makeFixture()
        let location = try #require(RepoReader.locate(pwd: repo.root))
        let snapshot = try #require(RepoReader.read(location, now: now))

        #expect(snapshot.base == "main")
        #expect(Set(snapshot.branches.map(\.name)) == ["main", "feat", "old"])
        let feat = try #require(snapshot.branches.first { $0.name == "feat" })
        #expect(feat.vsBase == AheadBehind(ahead: 2, behind: 0))
        #expect(feat.subject == "feat two")
        #expect(snapshot.branches.first { $0.name == "old" }?.vsBase == nil)
        #expect(snapshot.branches.first { $0.name == "main" }?.vsBase == nil)

        #expect(snapshot.worktrees.count == 3)
        #expect(snapshot.worktrees[0].isMain && snapshot.worktrees[0].branch == "main")
        #expect(snapshot.worktrees.first { ProjectResolver.canonical($0.path) == wt }?.branch == "feat")
        #expect(snapshot.worktrees.first { ProjectResolver.canonical($0.path) == det }?.branch == nil)
    }

    @Test func originHeadChoosesTheBase() throws {
        let (repo, _, _) = try makeFixture()
        try repo.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/feat")
        let snapshot = try readSnapshot(repo.root)
        #expect(snapshot.base == "feat")
    }

    @Test func aBranchNamedLikeATagKeepsItsName() throws {
        let repo = try TempRepo.make()
        try repo.git("tag", "release")
        try repo.git("branch", "release")
        let snapshot = try readSnapshot(repo.root)
        #expect(Set(snapshot.branches.map(\.name)) == ["main", "release"])
    }

    @Test func noMainOrMasterMeansNoBase() throws {
        let repo = try TempRepo.make()
        try repo.git("branch", "-m", "trunk")
        let snapshot = try readSnapshot(repo.root)
        #expect(snapshot.base == nil)
        #expect(snapshot.branches.allSatisfy { $0.vsBase == nil })
    }

    @Test func readsARebaseInProgress() throws {
        let (repo, _, det) = try makeFixture()
        let gitDir = try repo.git("rev-parse", "--absolute-git-dir", in: det)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try FileManager.default.createDirectory(atPath: gitDir + "/rebase-merge", withIntermediateDirectories: true)
        try "refs/heads/feat\n".write(toFile: gitDir + "/rebase-merge/head-name", atomically: true, encoding: .utf8)
        let snapshot = try readSnapshot(repo.root)
        #expect(snapshot.worktrees.first { ProjectResolver.canonical($0.path) == det }?.rebasing == "feat")
    }

    @Test func comparesAtMostMaxComparedBranches() throws {
        let (repo, _, _) = try makeFixture()
        let location = try #require(RepoReader.locate(pwd: repo.root))
        let snapshot = try #require(RepoReader.read(location, now: now, maxCompared: 0))
        #expect(snapshot.branches.allSatisfy { $0.vsBase == nil })
    }

    @Test func unusualBranchNamesRoundTrip() throws {
        let (repo, _, _) = try makeFixture()
        try repo.git("branch", "feature/ünï-✨")
        let snapshot = try readSnapshot(repo.root)
        let branch = try #require(snapshot.branches.first { $0.name == "feature/ünï-✨" })
        #expect(branch.vsBase == AheadBehind(ahead: 0, behind: 0))
    }

    @Test func detailsCountChangedFilesAndDirtyFiles() throws {
        let (repo, wt, _) = try makeFixture()
        FileManager.default.createFile(atPath: wt + "/scratch.txt", contents: Data("x".utf8))
        let snapshot = try readSnapshot(repo.root)
        let feat = try #require(snapshot.branches.first { $0.name == "feat" })
        let tree = snapshot.worktrees.first { $0.branch == "feat" }
        let details = RepoReader.details(for: feat, base: "main", worktree: tree, in: snapshot.root)
        #expect(details.changedFiles == 2)
        #expect(details.dirtyCount == 1)
        #expect(details.vsBase == AheadBehind(ahead: 2, behind: 0))

        let old = try #require(snapshot.branches.first { $0.name == "old" })
        let oldDetails = RepoReader.details(for: old, base: "main", worktree: nil, in: snapshot.root)
        #expect(oldDetails.vsBase == AheadBehind(ahead: 0, behind: 1))
        #expect(oldDetails.dirtyCount == nil)
    }
}
#endif
