#if os(macOS)
import Foundation
import LosttyRemote

/// Lostty Mobile: a new branch for a terminal the phone asks for, in a
/// worktree of its own (`<repo>/.claude/worktrees/<branch>`), started from
/// the repo's default branch as just fetched. Whatever else is open in the
/// repo's folder stays on its branch. Blocking: call it off the main thread.
enum WorktreeMaker {
    /// Inside the main checkout, as Claude Code keeps its worktrees.
    static let worktrees = ".claude/worktrees"

    struct Failure: Error, Equatable {
        var message: String
    }

    /// The new worktree's folder, or why it couldn't be made.
    static func make(branch: String, in folder: String) -> Result<String, Failure> {
        guard BranchName.isValid(branch) else { return .failure(Failure(message: "\"\(branch)\" isn't a branch name git takes.")) }
        guard let top = output(["rev-parse", "--show-toplevel"], in: folder) else {
            return .failure(Failure(message: "\((folder as NSString).lastPathComponent) isn't a git repository."))
        }
        // From a worktree, the main checkout: worktrees all live there.
        let common = output(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: top) ?? "\(top)/.git"
        let main = common.hasSuffix("/.git") ? String(common.dropLast(5)) : top
        let path = "\(main)/\(worktrees)/\(BranchName.folderName(branch))"
        guard !FileManager.default.fileExists(atPath: path) else {
            return .failure(Failure(message: "There's already a worktree for \(branch)."))
        }
        // Offline, or no origin: start from what's here.
        _ = git(["fetch", "--quiet", "origin"], in: main, timeout: 30)
        let exists = git(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"], in: main)?.status == 0
        let add = exists
            ? ["worktree", "add", path, branch]
            : ["worktree", "add", "--no-track", "-b", branch, path, base(in: main)]
        guard let result = git(add, in: main, timeout: 60) else {
            return .failure(Failure(message: "git took too long to make the worktree."))
        }
        guard result.status == 0 else { return .failure(Failure(message: reason(result.stderr))) }
        keepOutOfStatus(common: common, main: main)
        return .success(path)
    }

    /// `origin`'s default branch, else the first of main and master it
    /// has, else what's checked out.
    static func base(in repo: String) -> String {
        if let head = output(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: repo) { return head }
        for name in ["origin/main", "origin/master"]
        where git(["rev-parse", "--verify", "--quiet", name], in: repo)?.status == 0 {
            return name
        }
        return "HEAD"
    }

    /// The main checkout's `git status` doesn't list the worktrees: their
    /// folder goes in the repo's own exclude file (never a tracked
    /// .gitignore), unless something ignores it already.
    private static func keepOutOfStatus(common: String, main: String) {
        guard git(["check-ignore", "-q", "\(worktrees)/x"], in: main)?.status != 0 else { return }
        let info = URL(fileURLWithPath: common).appendingPathComponent("info")
        let exclude = info.appendingPathComponent("exclude")
        try? FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
        let line = "/\(worktrees)/\n"
        let text = existing.isEmpty || existing.hasSuffix("\n") ? existing + line : existing + "\n" + line
        try? text.write(to: exclude, atomically: true, encoding: .utf8)
    }

    /// git's complaint, first line, without "fatal: ".
    static func reason(_ stderr: String) -> String {
        let line = stderr.split(separator: "\n").first.map(String.init) ?? "git couldn't make the worktree."
        for prefix in ["fatal: ", "error: "] where line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
        return line
    }

    private static func output(_ args: [String], in dir: String) -> String? {
        guard let result = git(args, in: dir), result.status == 0 else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func git(_ args: [String], in dir: String, timeout: TimeInterval = 10) -> ProcessResult? {
        ProcessRunner.run(
            Git.executable, ["-C", dir] + args,
            environment: ["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"], timeout: timeout)
    }
}
#endif
