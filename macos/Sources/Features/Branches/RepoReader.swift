#if os(macOS)
import Foundation

/// Reads what the Branches panel shows from git. Blocking: call it off the
/// main thread.
enum RepoReader {
    /// Branches untouched this long go under "Older".
    static let olderAfter: TimeInterval = 30 * 24 * 3600
    /// At most this many branches are compared with the base per read, so a
    /// repo with hundreds of branches opens quickly.
    static let maxCompared = 50

    /// The repo `pwd` is in, from any of its worktrees. nil outside a repo,
    /// and for a home directory under git (dotfiles), as Skins does. A bare
    /// repo's root is its git dir, and none of its worktrees is main.
    static func locate(pwd: String, home: String = NSHomeDirectory()) -> RepoLocation? {
        guard let common = trimmed(Git.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: pwd)),
              let list = Git.run(["worktree", "list", "--porcelain"], in: pwd),
              let first = RepoParse.repoRoot(list) else { return nil }
        let root = ProjectResolver.canonical(first)
        guard root.lowercased() != ProjectResolver.canonical(home).lowercased() else { return nil }
        return RepoLocation(root: root, commonDir: ProjectResolver.canonical(common))
    }

    static func read(_ location: RepoLocation, now: Date = Date(), maxCompared: Int = RepoReader.maxCompared) -> RepoSnapshot? {
        let root = location.root
        guard let list = Git.run(["worktree", "list", "--porcelain"], in: root),
              let refs = Git.run(["for-each-ref", "refs/heads", "--format=\(RepoParse.branchFormat)"], in: root)
        else { return nil }

        let worktrees = RepoParse.worktrees(list).map { tree -> Worktree in
            var tree = tree
            tree.rebasing = rebasingBranch(in: tree.path)
            return tree
        }
        var branches = RepoParse.branches(refs)
        let base = resolveBase(in: root, branches: Set(branches.map(\.name)))
        if let base {
            let newestFirst = branches.indices.sorted { branches[$0].lastCommit > branches[$1].lastCommit }
            var compared = 0
            for index in newestFirst where compared < maxCompared {
                let branch = branches[index]
                guard branch.name != base, now.timeIntervalSince(branch.lastCommit) <= olderAfter else { continue }
                compared += 1
                branches[index].vsBase = aheadBehind(branch.name, base: base, in: root)
            }
        }
        return RepoSnapshot(root: root, commonDir: location.commonDir, base: base, branches: branches, worktrees: worktrees)
    }

    static func details(for branch: BranchInfo, base: String?, worktree: Worktree?, in root: String) -> BranchDetails {
        var details = BranchDetails()
        if let base, base != branch.name {
            details.vsBase = branch.vsBase ?? aheadBehind(branch.name, base: base, in: root)
            details.changedFiles = Git.run(
                ["diff", "--name-only", "refs/heads/\(base)...refs/heads/\(branch.name)"], in: root
            ).map(RepoParse.lineCount)
        }
        if let worktree {
            details.dirtyCount = Git.run(["status", "--porcelain"], in: worktree.path).map(RepoParse.lineCount)
        }
        return details
    }

    private static func aheadBehind(_ branch: String, base: String, in root: String) -> AheadBehind? {
        Git.run(["rev-list", "--left-right", "--count", "refs/heads/\(base)...refs/heads/\(branch)"], in: root)
            .flatMap(RepoParse.aheadBehind)
    }

    /// `origin/HEAD`'s branch when it exists locally, else main, else master.
    private static func resolveBase(in root: String, branches: Set<String>) -> String? {
        if let remote = trimmed(Git.run(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: root)),
           let slash = remote.firstIndex(of: "/") {
            let name = String(remote[remote.index(after: slash)...])
            if branches.contains(name) { return name }
        }
        return ["main", "master"].first(where: branches.contains)
    }

    /// The branch a rebase in progress in `worktree` is rewriting.
    private static func rebasingBranch(in worktree: String) -> String? {
        guard let gitDir = trimmed(Git.run(["rev-parse", "--absolute-git-dir"], in: worktree)) else { return nil }
        for dir in ["rebase-merge", "rebase-apply"] {
            if let contents = try? String(contentsOfFile: "\(gitDir)/\(dir)/head-name", encoding: .utf8) {
                return RepoParse.rebaseHead(contents)
            }
        }
        return nil
    }

    private static func trimmed(_ output: String?) -> String? {
        guard let value = output?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
#endif
