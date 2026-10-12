#if os(macOS)
import Foundation

/// One branch as the panel lists it.
struct BranchRow: Identifiable, Equatable, Sendable {
    var branch: BranchInfo
    var sessions: [BranchSession]
    var isBase: Bool
    var isRebasing: Bool
    /// Where the branch is checked out, when that's a linked worktree.
    var worktreePath: String?

    var id: String { branch.name }
}

/// The panel's groups, in display order.
struct BranchSections: Equatable, Sendable {
    /// Branches with sessions on them.
    var active: [BranchRow] = []
    var detached: [DetachedGroup] = []
    /// Other branches touched within `RepoReader.olderAfter`, and the base.
    var recent: [BranchRow] = []
    /// Shown collapsed.
    var older: [BranchRow] = []

    static let empty = BranchSections()

    /// Each group is newest commit first.
    static func build(_ snapshot: RepoSnapshot, placement: Placement, now: Date) -> BranchSections {
        let rebasing = Set(snapshot.worktrees.compactMap(\.rebasing))
        var linked: [String: String] = [:]
        for tree in snapshot.worktrees where !tree.isMain {
            if let branch = tree.branch, linked[branch] == nil { linked[branch] = tree.path }
        }
        let rows = snapshot.branches
            .sorted { $0.lastCommit != $1.lastCommit ? $0.lastCommit > $1.lastCommit : $0.name < $1.name }
            .map { branch in
                BranchRow(
                    branch: branch, sessions: placement.byBranch[branch.name] ?? [],
                    isBase: branch.name == snapshot.base, isRebasing: rebasing.contains(branch.name),
                    worktreePath: linked[branch.name])
            }

        var sections = BranchSections(detached: placement.detached)
        for row in rows {
            if !row.sessions.isEmpty {
                sections.active.append(row)
            } else if row.isBase || now.timeIntervalSince(row.branch.lastCommit) <= RepoReader.olderAfter {
                sections.recent.append(row)
            } else {
                sections.older.append(row)
            }
        }
        return sections
    }
}
#endif
