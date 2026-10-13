#if os(macOS)
import Foundation
import Testing
@testable import Lostty

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

    @Test func onlyWhatThePanelShowsCounts() {
        let refs = [
            "packed-refs", "refs/remotes/origin/HEAD", "worktrees/wt",
            "rebase-merge", "rebase-merge/head-name", "rebase-apply/head-name",
            "worktrees/wt/rebase-merge/head-name", "worktrees/wt/rebase-apply/head-name",
        ]
        for path in refs {
            #expect(RepoWatcher.classify("/r/.git/" + path, gitDir: "/r/.git") == .refs, "\(path)")
        }
        let ignored = [
            "FETCH_HEAD", "ORIG_HEAD", "COMMIT_EDITMSG", "config", "gc.log", "description",
            "fsmonitor--daemon/cookies/1234-0", "fsmonitor--daemon.ipc",
            "modules/s/objects/ab/cdef", "modules/s/HEAD", "lfs/objects/ab/cd/x",
            "sequencer/todo", "rebase-merge/done", "rebase-merge/msgnum", "rebase-apply/next",
            "worktrees/wt/ORIG_HEAD", "worktrees/wt/gitdir", "worktrees/wt/index.lock",
            "worktrees/wt/rebase-merge/done", "packed-refs.lock", "HEAD.lock", "index.lock",
        ]
        for path in ignored {
            #expect(RepoWatcher.classify("/r/.git/" + path, gitDir: "/r/.git") == nil, "\(path)")
        }
    }

    @Test func aSymlinkedGitDirMatchesEventsOnItsRealPath() throws {
        let dir = try TempRepo.makeDirectory()
        try FileManager.default.createDirectory(atPath: dir + "/real", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dir + "/link", withDestinationPath: dir + "/real")
        #expect(RepoWatcher.classify(dir + "/real/HEAD", gitDir: dir + "/link") == .refs)
        #expect(RepoWatcher.classify(dir + "/link/index", gitDir: dir + "/link") == .index)
        #expect(RepoWatcher.classify(dir + "/elsewhere/HEAD", gitDir: dir + "/link") == nil)
    }

    @Test func onlyThePathInsideTheGitDirCounts() {
        #expect(RepoWatcher.classify("/w/logs/svc/.git/refs/heads/main", gitDir: "/w/logs/svc/.git") == .refs)
        #expect(RepoWatcher.classify("/r/.git/refs/heads/logs/x", gitDir: "/r/.git") == .refs)
        #expect(RepoWatcher.classify("/r/.git/worktrees/wt/logs/HEAD", gitDir: "/r/.git") == nil)
    }

    /// git runs off the main actor, so a parallel suite that needs the main
    /// queue isn't held up while it does; only the watcher lives on main.
    @MainActor
    @Test func reportsACommit() async throws {
        let repo = try await Task.detached { try TempRepo.make() }.value
        var changes: Set<RepoWatcher.Change> = []
        let watcher = try #require(RepoWatcher(gitDir: repo.root + "/.git", latency: 0.1) { changes.formUnion($0) })
        try await Task.sleep(nanoseconds: 300_000_000)
        try await Task.detached { try repo.commit("second") }.value
        for _ in 0..<50 where !changes.contains(.refs) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(changes.contains(.refs))
        _ = watcher
    }
}
#endif
