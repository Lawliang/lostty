#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct RepoWatcherTests {
    @Test func classifiesGitDirChanges() {
        #expect(RepoWatcher.classify("/r/.git/refs/heads/main", gitDir: "/r/.git") == .refs)
        #expect(RepoWatcher.classify("/r/.git/HEAD", gitDir: "/r/.git") == .refs)
        #expect(RepoWatcher.classify("/r/.git/worktrees/wt/HEAD", gitDir: "/r/.git") == .refs)
        #expect(RepoWatcher.classify("/r/.git/index", gitDir: "/r/.git") == .index)
        #expect(RepoWatcher.classify("/r/.git/worktrees/wt/index", gitDir: "/r/.git") == .index)
        #expect(RepoWatcher.classify("/r/.git/objects/ab/cdef", gitDir: "/r/.git") == nil)
        #expect(RepoWatcher.classify("/r/.git/logs/HEAD", gitDir: "/r/.git") == nil)
        #expect(RepoWatcher.classify("/r/.git/refs/heads/main.lock", gitDir: "/r/.git") == nil)
    }

    @Test func onlyThePathInsideTheGitDirCounts() {
        #expect(RepoWatcher.classify("/w/logs/svc/.git/refs/heads/main", gitDir: "/w/logs/svc/.git") == .refs)
        #expect(RepoWatcher.classify("/r/.git/refs/heads/logs/x", gitDir: "/r/.git") == .refs)
        #expect(RepoWatcher.classify("/r/.git/worktrees/wt/logs/HEAD", gitDir: "/r/.git") == nil)
    }

    @Test func reportsACommit() async throws {
        let repo = try TempRepo.make()
        var changes: Set<RepoWatcher.Change> = []
        let watcher = try #require(RepoWatcher(gitDir: repo.root + "/.git", latency: 0.1) { changes.formUnion($0) })
        try await Task.sleep(nanoseconds: 300_000_000)
        try repo.commit("second")
        for _ in 0..<50 where !changes.contains(.refs) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(changes.contains(.refs))
        _ = watcher
    }
}
#endif
