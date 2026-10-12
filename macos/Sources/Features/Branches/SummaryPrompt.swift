#if os(macOS)
import Foundation

/// The prompt for one branch summary, capped at `limit` bytes.
enum SummaryPrompt {
    static let limit = 60_000

    /// Commits plus the whole diff when it fits; otherwise the file list
    /// (`diff --stat`) and as much of the diff as fits.
    static func build(branch: String, base: String, log: String, diff: String, stat: String) -> String {
        let commits = truncate(log, toBytes: limit / 4)
        let header = """
        Summarize what the git branch "\(branch)" changes compared with "\(base)", for a developer deciding \
        what the branch is about. Answer in 2 to 4 plain sentences: what it changes, and why if the commits say. \
        No headings, lists or preamble.

        Commits:
        \(commits.isEmpty ? "(none)" : commits)

        """
        let full = header + "Diff:\n" + diff
        if full.utf8.count <= limit { return full }

        let marker = "\n[diff truncated]"
        let capped = header + "Files changed:\n" + truncate(stat, toBytes: limit / 4) + "\nDiff (truncated):\n"
        let room = max(0, limit - capped.utf8.count - marker.utf8.count)
        return capped + truncate(diff, toBytes: room) + marker
    }

    /// The longest prefix of `text` within `bytes` UTF-8 bytes, whole characters only.
    static func truncate(_ text: String, toBytes bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let size = text[index].utf8.count
            if used + size > bytes { break }
            used += size
            end = text.index(after: index)
        }
        return String(text[..<end])
    }
}
#endif
