#if os(macOS)
import Foundation

/// Sessions on a detached HEAD at the same commit.
struct DetachedGroup: Identifiable, Equatable, Sendable {
    var sha: String
    var sessions: [BranchSession]
    var id: String { sha }
}

/// Which sessions are on which branch.
struct Placement: Equatable, Sendable {
    var byBranch: [String: [BranchSession]] = [:]
    var detached: [DetachedGroup] = []
}

enum SessionPlacement {
    /// Puts each session under the branch of the worktree its directory is
    /// in (the deepest one, so nested worktrees win), the branch a rebase
    /// there is rewriting, or a detached group. Sessions outside every
    /// worktree are left out. Paths compare canonically and case-insensitively.
    static func assign(_ sessions: [BranchSession], worktrees: [Worktree]) -> Placement {
        let keyed = worktrees.map { (tree: $0, key: ProjectResolver.canonical($0.path).lowercased()) }
        var placement = Placement()
        var detached: [String: [BranchSession]] = [:]
        var detachedOrder: [String] = []
        for session in sessions {
            let dir = ProjectResolver.canonical(session.pwd).lowercased()
            guard let tree = keyed
                .filter({ dir == $0.key || dir.hasPrefix($0.key + "/") })
                .max(by: { $0.key.count < $1.key.count })?.tree else { continue }
            if let branch = tree.branch ?? tree.rebasing {
                placement.byBranch[branch, default: []].append(session)
            } else {
                let sha = String(tree.head.prefix(7))
                if detached[sha] == nil { detachedOrder.append(sha) }
                detached[sha, default: []].append(session)
            }
        }
        placement.detached = detachedOrder.map { DetachedGroup(sha: $0, sessions: detached[$0] ?? []) }
        return placement
    }
}
#endif
