#if os(macOS)
import Foundation

/// Removes worktrees Lostty made once nothing in them can be lost: when
/// their last terminal is gone for good (it can't be undone back), and in
/// a sweep at launch. A worktree goes, with its branch, only when no tmux
/// pane is in it, it has no unsaved edits (ignored files don't count), and
/// every commit on its branch is in the repo's main branch. Each check runs
/// fresh. Blocking: call it off the main thread.
enum WorktreeCleanup {
    /// Set on worktrees Lostty makes, phone ones included. `+ticket working`
    /// renames only those that also have `lostty-base` (placeholders).
    static let madeKey = "lostty-made"
    static let baseKey = "lostty-base"

    enum Outcome: Equatable {
        /// Not a worktree Lostty made, or not a worktree at all.
        case notOurs
        /// A terminal is still in it.
        case inUse
        case removed(branch: String)
        /// Kept, and why, for the notice.
        case kept(branch: String, reason: String)
    }

    /// Off on quit and Restart to Update: those close terminals you expect back.
    nonisolated(unsafe) static var paused = false

    /// The terminal last in `pwd` closed for good: its worktree goes if it can.
    static func terminalClosed(pwd: String) -> Outcome {
        guard !paused, let top = Git.run(["rev-parse", "--show-toplevel"], in: pwd).map(trimmed) else { return .notOurs }
        return clean(top)
    }

    /// At launch, once "Continue your last session?" is settled and its
    /// terminals are back: a sweep of the zones' repos and the open
    /// terminals' repos.
    @MainActor
    static func sweepSoon(after delay: TimeInterval = 60) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let zones = CanvasController.shared.map { canvas in
                canvas.model.zones.compactMap { canvas.model.startFolder(ofZone: $0.id) }
            } ?? []
            Task.detached(priority: .utility) { _ = sweep(folders: zones + (panePaths() ?? [])) }
        }
    }

    /// The Lostty worktrees of each repo in `folders`, cleaned where they can be.
    static func sweep(folders: [String]) -> [Outcome] {
        let roots = Set(folders.compactMap(mainCheckout))
        return roots.flatMap { root in
            worktrees(of: root).filter { $0 != root }.map(clean)
        }
    }

    /// The worktree at `top`, removed with its branch when that loses nothing.
    static func clean(_ top: String) -> Outcome {
        guard !paused, let main = mainCheckout(top), main != top,
              let branch = Git.run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: top).map(trimmed),
              isLostty(branch, in: top) else { return .notOurs }
        let here = ProjectResolver.canonical(top)
        guard let panes = panePaths(), !panes.contains(where: { $0 == here || $0.hasPrefix(here + "/") }) else {
            return .inUse
        }
        guard let status = Git.run(["status", "--porcelain"], in: top) else {
            return .kept(branch: branch, reason: "git couldn't read it")
        }
        if !trimmed(status).isEmpty { return .kept(branch: branch, reason: "unsaved edits") }
        guard let base = mainBranch(in: main) else { return .kept(branch: branch, reason: "no main branch to compare with") }
        guard let ahead = Git.run(["rev-list", "--count", "--no-merges", "\(base)..\(branch)"], in: top)
            .map(trimmed).flatMap(Int.init) else {
            return .kept(branch: branch, reason: "git couldn't compare it with \(base)")
        }
        if ahead > 0 {
            return .kept(branch: branch, reason: "\(ahead) commit\(ahead == 1 ? "" : "s") not in \(base)")
        }
        guard Git.run(["worktree", "remove", top], in: main, timeout: 30) != nil else {
            return .kept(branch: branch, reason: "git wouldn't remove it")
        }
        _ = Git.run(["branch", "-D", branch], in: main)
        return .removed(branch: branch)
    }

    /// Whether Lostty made `branch`'s worktree.
    static func isLostty(_ branch: String, in dir: String) -> Bool {
        [madeKey, baseKey].contains { Git.run(["config", "--get", "branch.\(branch).\($0)"], in: dir) != nil }
    }

    /// The repo's main branch, local: origin's default when it has one,
    /// else main, else master.
    static func mainBranch(in repo: String) -> String? {
        var names = ["main", "master"]
        if let head = Git.run(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: repo).map(trimmed),
           head.hasPrefix("origin/") {
            names.insert(String(head.dropFirst("origin/".count)), at: 0)
        }
        return names.first { Git.run(["show-ref", "--verify", "--quiet", "refs/heads/\($0)"], in: repo) != nil }
    }

    /// The main checkout of the repo holding `folder`.
    private static func mainCheckout(_ folder: String) -> String? {
        guard let common = Git.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: folder)
            .map(trimmed), common.hasSuffix("/.git") else { return nil }
        return String(common.dropLast("/.git".count))
    }

    private static func worktrees(of root: String) -> [String] {
        (Git.run(["worktree", "list", "--porcelain"], in: root) ?? "")
            .split(separator: "\n")
            .filter { $0.hasPrefix("worktree ") }
            .map { String($0.dropFirst("worktree ".count)) }
    }

    /// Where every tmux pane is: Lostty's terminals, the phone's included.
    /// Nil when a server may be running but didn't answer.
    private static func panePaths() -> [String]? {
        guard let listed = TmuxClient().run(["list-panes", "-a", "-F", "#{pane_current_path}"]) else {
            return TmuxClient.serverSocketExists ? nil : []
        }
        return listed.split(separator: "\n").map { ProjectResolver.canonical(String($0)) }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension LosttyNotifications {
    /// "Kept wt-3 in hustleberry: 2 commits not in main."
    func postKeptWorktree(branch: String, folder: String, reason: String) {
        let repo = (folder.components(separatedBy: "/" + WorktreeMaker.worktrees + "/")[0] as NSString).lastPathComponent
        post(LosttyNotification(
            kind: .keptWorktree(branch: branch),
            title: "Kept \(branch) in \(repo)",
            detail: "Its worktree stays: \(reason)."))
    }
}
#endif
