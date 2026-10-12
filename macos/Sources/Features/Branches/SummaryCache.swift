#if os(macOS)
import Foundation

/// A branch summary from Claude, for the branch tip it described.
struct BranchSummary: Codable, Equatable, Sendable {
    var tip: String
    var text: String
    var createdAt: Date

    /// The branch moved since: the summary may no longer describe it.
    func isOutdated(tip current: String) -> Bool { tip != current }
}

/// Summaries kept across launches, so a branch is only summarized again
/// when someone asks.
@MainActor
final class SummaryCache {
    static let shared = SummaryCache(url: defaultURL)

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/branch-summaries.json")
    }

    private let url: URL
    private var entries: [String: BranchSummary]

    /// An unreadable file reads as empty; the next store rewrites it.
    init(url: URL) {
        self.url = url
        entries = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: BranchSummary].self, from: $0) } ?? [:]
    }

    /// `repo` is the repo's common git dir, the same for all its worktrees.
    func summary(repo: String, branch: String) -> BranchSummary? {
        entries[Self.key(repo, branch)]
    }

    func store(_ summary: BranchSummary, repo: String, branch: String) {
        entries[Self.key(repo, branch)] = summary
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func key(_ repo: String, _ branch: String) -> String { repo + "\n" + branch }
}
#endif
