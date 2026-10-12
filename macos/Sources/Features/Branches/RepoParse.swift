#if os(macOS)
import Foundation

/// Parsers for the git output the Branches panel reads. Pure.
enum RepoParse {
    /// `for-each-ref --format`: name, sha, committer time, upstream, track,
    /// subject — tab separated, subject last because it may contain tabs.
    static let branchFormat =
        "%(refname:lstrip=2)%09%(objectname)%09%(committerdate:unix)%09%(upstream:short)%09%(upstream:track)%09%(subject)"

    static func branches(_ output: String) -> [BranchInfo] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 6, !f[0].isEmpty, let seconds = TimeInterval(f[2]) else { return nil }
            return BranchInfo(
                name: f[0], tip: f[1], lastCommit: Date(timeIntervalSince1970: seconds),
                subject: f[5], upstream: upstream(name: f[3], track: f[4]), vsBase: nil)
        }
    }

    /// `%(upstream:track)`: "", "[gone]", "[ahead 1]", "[behind 2]", "[ahead 1, behind 2]".
    static func upstream(name: String, track: String) -> Upstream {
        guard !name.isEmpty else { return .none }
        if track == "[gone]" { return .gone(name: name) }
        var ahead = 0
        var behind = 0
        for part in track.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let count = Int(words[1]) else { continue }
            if words[0] == "ahead" { ahead = count } else if words[0] == "behind" { behind = count }
        }
        return .tracking(name: name, ahead: ahead, behind: behind)
    }

    /// `worktree list --porcelain`. The first entry is the main worktree, or
    /// in a bare repo the bare git dir, so there none is main.
    /// Bare entries and prunable ones (their folder is gone) are skipped.
    static func worktrees(_ porcelain: String) -> [Worktree] {
        var result: [Worktree] = []
        for (index, block) in porcelain.components(separatedBy: "\n\n").enumerated() {
            var path: String?
            var head = ""
            var branch: String?
            var skip = false
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("HEAD ") {
                    head = String(line.dropFirst("HEAD ".count))
                } else if line.hasPrefix("branch ") {
                    branch = shortBranch(String(line.dropFirst("branch ".count)))
                } else if line == "bare" || line.hasPrefix("prunable") {
                    skip = true
                }
            }
            guard let path, !skip else { continue }
            result.append(Worktree(path: path, head: head, branch: branch, rebasing: nil, isMain: index == 0))
        }
        return result
    }

    /// The repo's own folder from `worktree list --porcelain`: the first
    /// entry, which is the main worktree, or the git dir itself for a bare
    /// repo (whose worktrees are all linked ones).
    static func repoRoot(_ porcelain: String) -> String? {
        for line in porcelain.split(separator: "\n") {
            if line.hasPrefix("worktree ") { return String(line.dropFirst("worktree ".count)) }
        }
        return nil
    }

    static func shortBranch(_ ref: String) -> String {
        ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }

    /// `rev-list --left-right --count base...branch` prints "<behind>\t<ahead>".
    static func aheadBehind(_ output: String) -> AheadBehind? {
        let f = output.split(whereSeparator: { $0 == "\t" || $0 == " " || $0.isNewline })
        guard f.count == 2, let behind = Int(f[0]), let ahead = Int(f[1]) else { return nil }
        return AheadBehind(ahead: ahead, behind: behind)
    }

    /// A rebase's `head-name` file: "refs/heads/feat\n" → "feat".
    static func rebaseHead(_ contents: String) -> String? {
        let ref = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ref.hasPrefix("refs/heads/") else { return nil }
        return shortBranch(ref)
    }

    static func lineCount(_ output: String) -> Int {
        output.split(whereSeparator: \.isNewline).count
    }
}
#endif
