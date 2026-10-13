#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

/// Real repos in a temporary folder: an "origin" (bare) and a clone of it.
struct WorktreeMakerTests {
    let root: URL
    var origin: String { root.appendingPathComponent("origin.git").path }
    var clone: String { root.appendingPathComponent("app").path }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("worktree-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let seed = root.appendingPathComponent("seed").path
        try git(["init", "-q", "-b", "main", seed], in: root.path)
        try "hi\n".write(toFile: seed + "/README", atomically: true, encoding: .utf8)
        try git(["add", "README"], in: seed)
        try git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "first"], in: seed)
        try git(["clone", "-q", "--bare", seed, origin], in: root.path)
        try git(["clone", "-q", origin, clone], in: root.path)
        // The clone sits on another branch: the new one still starts from main.
        try git(["checkout", "-qb", "elsewhere"], in: clone)
    }

    @discardableResult
    private func git(_ args: [String], in dir: String) throws -> String {
        let result = try #require(ProcessRunner.run(Git.executable, ["-C", dir] + args, timeout: 20))
        #expect(result.status == 0, "git \(args.joined(separator: " ")): \(result.stderr)")
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func aNewBranchGetsItsOwnWorktreeFromTheDefaultBranch() throws {
        let path = try WorktreeMaker.make(branch: "feature/login", in: clone).get()
        // git names the folder by its real path (/private/var, not /var).
        let top = try git(["rev-parse", "--show-toplevel"], in: clone)
        #expect(path == top + "/.claude/worktrees/feature-login")
        #expect(try git(["rev-parse", "--abbrev-ref", "HEAD"], in: path) == "feature/login")
        #expect(try git(["rev-parse", "HEAD"], in: path) == git(["rev-parse", "origin/main"], in: clone))
        // The clone's own folder stays where it was, and doesn't list it.
        #expect(try git(["rev-parse", "--abbrev-ref", "HEAD"], in: clone) == "elsewhere")
        #expect(try git(["status", "--porcelain"], in: clone).isEmpty)
        // No upstream: it isn't main.
        #expect(ProcessRunner.run(Git.executable, ["-C", path, "rev-parse", "@{u}"], timeout: 5)?.status != 0)
    }

    @Test func fromAWorktreeTheNewOneGoesInTheMainCheckout() throws {
        let first = try WorktreeMaker.make(branch: "one", in: clone).get()
        let second = try WorktreeMaker.make(branch: "two", in: first).get()
        #expect(second == (try git(["rev-parse", "--show-toplevel"], in: clone)) + "/.claude/worktrees/two")
    }

    @Test func anExistingBranchIsCheckedOutInItsWorktree() throws {
        try git(["branch", "kept", "main"], in: clone)
        let path = try WorktreeMaker.make(branch: "kept", in: clone).get()
        #expect(try git(["rev-parse", "--abbrev-ref", "HEAD"], in: path) == "kept")
    }

    @Test func whatCantBeMadeSaysWhy() throws {
        _ = try WorktreeMaker.make(branch: "twice", in: clone).get()
        #expect(WorktreeMaker.make(branch: "twice", in: clone) == .failure(.init(message: "There's already a worktree for twice.")))
        #expect(WorktreeMaker.make(branch: "bad name", in: clone)
            == .failure(.init(message: "\"bad name\" isn't a branch name git takes.")))
        #expect(WorktreeMaker.make(branch: "x", in: root.path)
            == .failure(.init(message: "\(root.lastPathComponent) isn't a git repository.")))
        // Checked out already (here, the clone's own branch): git says so.
        guard case .failure(let failure) = WorktreeMaker.make(branch: "elsewhere", in: clone) else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure.message.contains("elsewhere"))
    }

    @Test func gitsComplaintReadsPlainly() {
        #expect(WorktreeMaker.reason("fatal: a branch named 'x' already exists\nmore") == "a branch named 'x' already exists")
        #expect(WorktreeMaker.reason("") == "git couldn't make the worktree.")
    }
}
#endif
