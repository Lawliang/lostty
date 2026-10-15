#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ProjectLabelTests {
    @Test func repoRootShowsItsFolderAndBranch() throws {
        let repo = try TempRepo.make()
        try repo.git("checkout", "-q", "-b", "skins")
        #expect(ProjectLabel.read(pwd: repo.root) == ProjectLabel(project: "repo", branch: "skins"))
    }

    @Test func subfolderShowsItsRepo() throws {
        let repo = try TempRepo.make()
        let sub = repo.root + "/src/deep"
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        #expect(ProjectLabel.read(pwd: sub) == ProjectLabel(project: "repo", branch: "main"))
    }

    @Test func worktreeShowsTheRepoNotItsOwnFolder() throws {
        let repo = try TempRepo.make()
        let tree = try TempRepo.makeDirectory() + "/tree"
        try repo.git("worktree", "add", "-q", "-b", "pill", tree)
        #expect(ProjectLabel.read(pwd: tree) == ProjectLabel(project: "repo", branch: "pill"))
    }

    @Test func detachedHeadShowsNoBranch() throws {
        let repo = try TempRepo.make()
        try repo.git("checkout", "-q", "--detach")
        #expect(ProjectLabel.read(pwd: repo.root) == ProjectLabel(project: "repo", branch: nil))
    }

    @Test func outsideARepoShowsNothing() throws {
        let dir = try TempRepo.makeDirectory()
        #expect(ProjectLabel.read(pwd: dir) == nil)
    }

    @Test func aRepoInTheHomeFolderDoesNotCount() throws {
        let repo = try TempRepo.make()
        let sub = repo.root + "/notes"
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        #expect(ProjectLabel.read(pwd: sub, home: repo.root) == nil)
    }

    @Test func textJoinsProjectAndBranch() {
        #expect(ProjectLabel(project: "lostty", branch: "skins").text == "lostty/skins")
        #expect(ProjectLabel(project: "lostty", branch: nil).text == "lostty")
    }
}
#endif
