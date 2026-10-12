#if os(macOS)
import Combine
import Foundation
import Testing
@testable import Ghostty

/// Scripted inputs for a BranchesModel.
@MainActor
final class FakeBranchesWorld {
    var pwds: [UUID: String] = [:]
    /// pwd prefix → location.
    var repos: [String: RepoLocation] = [:]
    /// root → snapshots to hand out in order; the last repeats. nil = git failed.
    var snapshots: [String: [RepoSnapshot?]] = [:]
    var panes: [BranchSession] = []
    var claude: String? = "/fake/claude"
    var summaryResult: Result<String, SummaryError> = .success("Adds X.")
    var slowPwd: String?
    /// Holds a locate of `slowPwd` until opened.
    let gate = Gate()
    var watching: [String] = []
    let changes = PassthroughSubject<Void, Never>()
    let cache: SummaryCache

    init() throws {
        cache = SummaryCache(url: URL(fileURLWithPath: try TempRepo.makeDirectory()).appendingPathComponent("s.json"))
    }

    func environment() -> BranchesModel.Environment {
        let repos = repos
        let slowPwd = slowPwd
        let gate = gate
        let claude = claude
        let summaryResult = summaryResult
        let store = SnapshotQueue(snapshots)
        return BranchesModel.Environment(
            pwd: { self.pwds[$0] },
            locate: { pwd in
                if pwd == slowPwd { gate.enterAndWait() }
                return repos.first { pwd.hasPrefix($0.key) }?.value
            },
            read: { location, _ in store.next(location.root) },
            details: { _, _, _, _ in BranchDetails(vsBase: nil, changedFiles: 3, dirtyCount: 1) },
            panes: { self.panes },
            phoneSessions: { [] },
            locateClaude: { claude },
            summarize: { _, _, _, _, _ in summaryResult },
            watch: { dir, _ in self.watching.append(dir); return NSObject() },
            changes: { self.changes.eraseToAnyPublisher() },
            phoneInterval: 3600,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            cache: cache)
    }
}

/// Lets a test hold a background call until it says go.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var entered = false

    var hasEntered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entered
    }

    func enterAndWait() {
        lock.lock()
        entered = true
        lock.unlock()
        semaphore.wait()
    }

    func open() { semaphore.signal() }
}

/// Hands out each root's snapshots in order, repeating the last.
final class SnapshotQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [String: [RepoSnapshot?]]
    init(_ queues: [String: [RepoSnapshot?]]) { self.queues = queues }
    func next(_ root: String) -> RepoSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard var queue = queues[root], let first = queue.first else { return nil }
        if queue.count > 1 { queue.removeFirst(); queues[root] = queue }
        return first
    }
}

@MainActor
struct BranchesModelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ root: String, branches: [String] = ["main", "feat"]) -> RepoSnapshot {
        RepoSnapshot(
            root: root, commonDir: root + "/.git", base: "main",
            branches: branches.map {
                BranchInfo(name: $0, tip: "\($0)-tip", lastCommit: now, subject: "s", upstream: .none, vsBase: nil)
            },
            worktrees: [Worktree(path: root, head: "h", branch: "main", rebasing: nil, isMain: true)])
    }

    private func world(pane: UUID, pwd: String = "/a/src") throws -> FakeBranchesWorld {
        let world = try FakeBranchesWorld()
        world.pwds[pane] = pwd
        world.repos["/a"] = RepoLocation(root: "/a", commonDir: "/a/.git")
        world.repos["/b"] = RepoLocation(root: "/b", commonDir: "/b/.git")
        world.snapshots["/a"] = [snapshot("/a")]
        world.snapshots["/b"] = [snapshot("/b")]
        return world
    }

    @Test func noFocusedPane() async throws {
        let world = try FakeBranchesWorld()
        let model = BranchesModel(env: world.environment())
        await model.open(focused: nil).value
        #expect(model.status == .noPane)
    }

    @Test func aPaneOutsideARepo() async throws {
        let pane = UUID()
        let model = BranchesModel(env: try world(pane: pane, pwd: "/elsewhere").environment())
        await model.open(focused: pane).value
        #expect(model.status == .notARepo)
    }

    @Test func loadsTheRepoAndPlacesSessions() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.panes = [BranchSession(origin: .pane(pane), title: "zsh", pwd: "/a/src", agent: .working)]
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        #expect(model.status == .loaded)
        #expect(model.snapshot?.root == "/a")
        #expect(model.sections.active.map(\.id) == ["main"])
        #expect(model.sections.active[0].sessions.first?.agent == .working)
        #expect(world.watching == ["/a/.git"])
    }

    @Test func keepsLastSnapshotWhenRefreshFails() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.snapshots["/a"] = [snapshot("/a"), nil]
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        await model.reload()
        #expect(model.status == .loaded)
        #expect(model.refreshFailed)
        #expect(model.snapshot?.root == "/a")
    }

    @Test func aFirstLoadFailureShowsFailed() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.snapshots["/a"] = [nil]
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        #expect(model.status == .failed)
    }

    @Test func laterFocusWinsOverSlowerEarlierLoad() async throws {
        let slow = UUID()
        let fast = UUID()
        let world = try world(pane: slow, pwd: "/a/slow")
        world.pwds[fast] = "/b/src"
        world.slowPwd = "/a/slow"
        let model = BranchesModel(env: world.environment())
        await model.open(focused: nil).value
        let first = Task { await model.setFocus(slow) }
        while !world.gate.hasEntered { try await Task.sleep(nanoseconds: 10_000_000) }
        await model.setFocus(fast)
        world.gate.open()
        await first.value
        #expect(model.snapshot?.root == "/b")
    }

    @Test func expandingARowLoadsItsDetails() async throws {
        let pane = UUID()
        let model = BranchesModel(env: try world(pane: pane).environment())
        await model.open(focused: pane).value
        model.toggle("feat")
        #expect(model.expanded == ["feat"])
        await model.loadDetails("feat")
        #expect(model.details["feat"]?.changedFiles == 3)
        model.toggle("feat")
        #expect(model.expanded.isEmpty)
    }

    @Test func summarizeStoresTheSummary() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        await model.lookUpClaude()
        #expect(model.canSummarize)
        await model.summarizeNow("feat")
        #expect(model.summaryState(for: "feat") == nil)
        #expect(model.summary(for: "feat")?.text == "Adds X.")
        #expect(model.summary(for: "feat")?.tip == "feat-tip")
    }

    @Test func aFailedSummaryShowsWhy() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.summaryResult = .failure(.failed("Not logged in"))
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        await model.lookUpClaude()
        await model.summarizeNow("feat")
        #expect(model.summaryState(for: "feat") == .failed("Not logged in"))
    }

    @Test func aSummaryFailureDoesNotShowOnAnotherRepo() async throws {
        let pane = UUID()
        let other = UUID()
        let world = try world(pane: pane)
        world.pwds[other] = "/b/src"
        world.summaryResult = .failure(.failed("Not logged in"))
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        await model.lookUpClaude()
        await model.summarizeNow("feat")
        #expect(model.summaryState(for: "feat") == .failed("Not logged in"))
        await model.setFocus(other)
        #expect(model.snapshot?.root == "/b")
        #expect(model.summaryState(for: "feat") == nil)
    }

    @Test func aStaleSessionsChangeDoesNotOverrideTheLatestFocus() async throws {
        let pane = UUID()
        let fast = UUID()
        let world = try world(pane: pane)
        world.pwds[fast] = "/b/src"
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        model.focusChanged(fast)
        world.changes.send()
        for _ in 0..<100 where model.snapshot?.root != "/b" {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(model.snapshot?.root == "/b")
    }

    @Test func noClaudeMeansNoSummaries() async throws {
        let pane = UUID()
        let world = try world(pane: pane)
        world.claude = nil
        let model = BranchesModel(env: world.environment())
        await model.open(focused: pane).value
        await model.lookUpClaude()
        #expect(model.canSummarize == false)
        await model.summarizeNow("feat")
        #expect(model.summary(for: "feat") == nil)
    }

    @Test func closingStopsWatchingAndResets() async throws {
        let pane = UUID()
        let model = BranchesModel(env: try world(pane: pane).environment())
        await model.open(focused: pane).value
        model.close()
        #expect(model.status == .closed)
        #expect(model.isOpen == false)
        #expect(model.snapshot == nil)
    }
}
#endif
