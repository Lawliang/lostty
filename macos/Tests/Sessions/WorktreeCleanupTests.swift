#if os(macOS)
import Foundation
import Testing
@testable import Lostty

/// Real repos in a temporary folder, with worktrees made as Lostty makes them.
struct WorktreeCleanupTests {
    let root: URL
    var repo: String { root.appendingPathComponent("app").path }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanup-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main", repo], in: root.path)
        try "build/\n".write(toFile: repo + "/.gitignore", atomically: true, encoding: .utf8)
        try git(["add", ".gitignore"], in: repo)
        try commit("first", in: repo)
    }

    @discardableResult
    private func git(_ args: [String], in dir: String) throws -> String {
        let result = try #require(ProcessRunner.run(Git.executable, ["-C", dir] + args, timeout: 20))
        #expect(result.status == 0, "git \(args.joined(separator: " ")): \(result.stderr)")
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit(_ message: String, in dir: String) throws {
        try git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", message], in: dir)
    }

    private func made(_ branch: String) throws -> String {
        try WorktreeMaker.make(branch: branch, in: repo).get()
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    @Test func anUnusedWorktreeGoesWithItsBranch() throws {
        let path = try made("wt-1")
        #expect(WorktreeCleanup.terminalClosed(pwd: path) == .removed(branch: "wt-1"))
        #expect(!exists(path))
        #expect(try git(["branch", "--list", "wt-1"], in: repo).isEmpty)
    }

    @Test func workMergedIntoMainGoes() throws {
        let path = try made("login")
        try commit("work", in: path)
        try git(["merge", "-q", "--no-ff", "-m", "merge", "login"], in: repo)
        #expect(WorktreeCleanup.clean(path) == .removed(branch: "login"))
    }

    @Test func workNotInMainStays() throws {
        let path = try made("login")
        try commit("work", in: path)
        #expect(WorktreeCleanup.clean(path) == .kept(branch: "login", reason: "1 commit not in main"))
        #expect(exists(path))
    }

    @Test func unsavedEditsStayButIgnoredFilesDont() throws {
        let path = try made("edits")
        try FileManager.default.createDirectory(atPath: path + "/build", withIntermediateDirectories: true)
        try "x".write(toFile: path + "/build/out", atomically: true, encoding: .utf8)
        try "x".write(toFile: path + "/notes.txt", atomically: true, encoding: .utf8)
        #expect(WorktreeCleanup.clean(path) == .kept(branch: "edits", reason: "unsaved edits"))
        try FileManager.default.removeItem(atPath: path + "/notes.txt")
        #expect(WorktreeCleanup.clean(path) == .removed(branch: "edits"))
    }

    @Test func worktreesLosttyDidntMakeAndTheMainCheckoutStay() throws {
        let path = root.appendingPathComponent("mine").path
        try git(["worktree", "add", "-q", "-b", "mine", path], in: repo)
        #expect(WorktreeCleanup.clean(path) == .notOurs)
        #expect(WorktreeCleanup.clean(repo) == .notOurs)
        #expect(exists(path))
    }

    @Test func theSweepCleansEveryLosttyWorktreeOfTheRepo() throws {
        let unused = try made("wt-1")
        let busy = try made("wt-2")
        try commit("work", in: busy)
        let outcomes = WorktreeCleanup.sweep(folders: [repo + "/.claude"])
        #expect(outcomes.contains(.removed(branch: "wt-1")))
        #expect(outcomes.contains(.kept(branch: "wt-2", reason: "1 commit not in main")))
        #expect(!exists(unused) && exists(busy))
    }
}
#endif
