#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct SummaryCacheTests {
    private func url() throws -> URL {
        URL(fileURLWithPath: try TempRepo.makeDirectory()).appendingPathComponent("nested/summaries.json")
    }

    @Test func storesAndReloadsByRepoAndBranch() throws {
        let file = try url()
        let summary = BranchSummary(tip: "abc", text: "Adds X.", createdAt: Date(timeIntervalSince1970: 100))
        SummaryCache(url: file).store(summary, repo: "/r/.git", branch: "feat")
        let reloaded = SummaryCache(url: file)
        #expect(reloaded.summary(repo: "/r/.git", branch: "feat") == summary)
        #expect(reloaded.summary(repo: "/r/.git", branch: "main") == nil)
        #expect(reloaded.summary(repo: "/other/.git", branch: "feat") == nil)
    }

    @Test func aSummaryIsOutdatedOnceTheTipMoves() {
        let summary = BranchSummary(tip: "abc", text: "t", createdAt: Date())
        #expect(summary.isOutdated(tip: "abc") == false)
        #expect(summary.isOutdated(tip: "def"))
    }

    @Test func aCorruptFileReadsAsEmptyAndIsRewritten() throws {
        let file = try url()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        let cache = SummaryCache(url: file)
        #expect(cache.summary(repo: "/r/.git", branch: "feat") == nil)
        cache.store(BranchSummary(tip: "1", text: "t", createdAt: Date()), repo: "/r/.git", branch: "feat")
        #expect(SummaryCache(url: file).summary(repo: "/r/.git", branch: "feat")?.tip == "1")
    }
}
#endif
