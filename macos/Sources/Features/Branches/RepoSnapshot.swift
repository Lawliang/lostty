#if os(macOS)
import Foundation

/// Commits a branch has that another doesn't (ahead), and the reverse (behind).
struct AheadBehind: Equatable, Sendable {
    var ahead: Int
    var behind: Int
}

/// A branch's remote-tracking branch, as `for-each-ref` reports it.
enum Upstream: Equatable, Sendable {
    case none
    case tracking(name: String, ahead: Int, behind: Int)
    /// Configured, but the remote branch was deleted.
    case gone(name: String)
}

/// A local branch.
struct BranchInfo: Equatable, Sendable {
    var name: String
    var tip: String
    var lastCommit: Date
    var subject: String
    var upstream: Upstream
    /// Against the repo's base branch; nil for the base itself and for
    /// branches not compared yet (older ones, until their row is expanded).
    var vsBase: AheadBehind?
}

/// A checkout of the repo: the main one or a linked worktree.
struct Worktree: Equatable, Sendable {
    var path: String
    var head: String
    /// nil when HEAD is detached.
    var branch: String?
    /// The branch a rebase in progress here is rewriting.
    var rebasing: String?
    var isMain: Bool
}

/// Where a repo is: every worktree of it maps to the same location.
struct RepoLocation: Hashable, Sendable {
    /// The main worktree.
    var root: String
    /// The git directory all worktrees share.
    var commonDir: String
}

/// One read of a repo, everything a closed row shows.
struct RepoSnapshot: Equatable, Sendable {
    var root: String
    var commonDir: String
    var base: String?
    var branches: [BranchInfo]
    var worktrees: [Worktree]

    var name: String { (root as NSString).lastPathComponent }
}

/// What an expanded row adds; read when the row opens.
struct BranchDetails: Equatable, Sendable {
    var vsBase: AheadBehind?
    var changedFiles: Int?
    /// Uncommitted changes where the branch is checked out.
    var dirtyCount: Int?
}
#endif
