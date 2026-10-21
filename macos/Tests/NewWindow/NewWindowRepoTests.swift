#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct NewWindowRepoTests {
    @Test func aMainCheckoutIsItsOwnRoot() {
        let repo = NewWindowRepo.parse("/r/app\n/r/app/.git\nmain\n")
        #expect(repo == NewWindowRepo(root: "/r/app", checkout: "/r/app", commonDir: "/r/app/.git", branch: "main"))
        #expect(repo?.name == "app")
    }

    @Test func aWorktreesRootIsTheMainCheckout() {
        let repo = NewWindowRepo.parse("/r/app/.claude/worktrees/x\n/r/app/.git\nx\n")
        #expect(repo?.root == "/r/app")
        #expect(repo?.checkout == "/r/app/.claude/worktrees/x")
    }

    @Test func aDetachedHeadHasNoBranch() {
        #expect(NewWindowRepo.parse("/r/app\n/r/app/.git\nHEAD\n")?.branch == nil)
    }

    @Test func outsideARepoThereIsNone() {
        #expect(NewWindowRepo.parse("") == nil)
    }

    @Test func aBranchsWorktreeIsOneFolderUnderTheRoot() {
        let repo = NewWindowRepo(root: "/r/app", checkout: "/r/app", commonDir: "/r/app/.git", branch: "main")
        #expect(repo.worktreePath(for: "fix/login") == "/r/app/.claude/worktrees/fix-login")
    }

    @Test func makingAWorktreeLeavesTheOtherCheckoutOnItsBranch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NewWindowRepoTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.path
        for args in [["init", "-q", "-b", "main"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"]] {
            #expect(ProcessRunner.run(Git.executable, ["-C", path] + args, timeout: 10)?.status == 0)
        }
        let repo = try #require(NewWindowRepo.read(pwd: path))
        let made = NewWindowRepo.addWorktree(repo, branch: "feature/a")
        let worktree = try made.get()
        #expect(NewWindowRepo.read(pwd: worktree)?.branch == "feature/a")
        #expect(NewWindowRepo.read(pwd: path)?.branch == "main")
        // Kept out of the main checkout's status.
        #expect(Git.run(["status", "--porcelain"], in: path) == "")
        #expect(NewWindowRepo.addWorktree(repo, branch: "bad..name") == .failure(.init(message: "“bad..name” isn't a valid branch name.")))
    }
}
#endif
