#if os(macOS)
import AppKit
import Combine
import Foundation

/// What one window's Branches panel shows. Does nothing until opened, and
/// stops watching when closed.
@MainActor
final class BranchesModel: ObservableObject {
    enum Status: Equatable {
        case closed
        case noPane
        case notARepo
        case loading
        case loaded
        /// The first read of this repo failed.
        case failed
    }

    enum SummaryState: Equatable {
        case running
        case failed(String)
    }

    enum ClaudeLookup: Equatable {
        case unknown
        case found(String)
        case missing
    }

    /// Everything the model reads from the outside world, so tests can
    /// script it. `live` is the app's.
    struct Environment {
        var pwd: @MainActor (UUID) -> String?
        var locate: @Sendable (String) -> RepoLocation?
        var read: @Sendable (RepoLocation, Date) -> RepoSnapshot?
        var details: @Sendable (BranchInfo, String?, Worktree?, String) -> BranchDetails
        var panes: @MainActor () -> [BranchSession]
        var phoneSessions: @Sendable () -> [BranchSession]
        var locateClaude: @Sendable () -> String?
        var summarize: @Sendable (String, String, String, String, RunHandle) -> Result<String, SummaryError>
        var watch: @MainActor (String, @escaping @MainActor (Set<RepoWatcher.Change>) -> Void) -> AnyObject?
        /// Fires when panes, their folders or agent states change.
        var changes: @MainActor () -> AnyPublisher<Void, Never>
        var phoneInterval: TimeInterval
        var now: () -> Date
        var cache: SummaryCache

        static var live: Environment {
            Environment(
                pwd: { (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: $0)?.pwd },
                locate: { RepoReader.locate(pwd: $0) },
                read: { RepoReader.read($0, now: $1) },
                details: { RepoReader.details(for: $0, base: $1, worktree: $2, in: $3) },
                panes: { SessionLocator.panes() },
                phoneSessions: { SessionLocator.phoneSessions() },
                locateClaude: { ClaudeCLI.locate() },
                summarize: { BranchSummarizer.run(branch: $0, base: $1, root: $2, claude: $3, handle: $4) },
                watch: { RepoWatcher(gitDir: $0, onChange: $1) },
                changes: {
                    Publishers.Merge4(
                        ClaudeRuntime.shared.$phases.map { _ in () },
                        ClaudeRuntime.shared.$awaiting.map { _ in () },
                        ClaudeUsageRuntime.shared.$sessions.map { _ in () },
                        SkinsRuntime.shared.manager.$panes.map { _ in () })
                    .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                    .eraseToAnyPublisher()
                },
                phoneInterval: 5,
                now: Date.init,
                cache: .shared)
        }
    }

    @Published private(set) var status: Status = .closed
    @Published private(set) var snapshot: RepoSnapshot?
    @Published private(set) var sections: BranchSections = .empty
    /// A refresh failed; the last snapshot is still showing.
    @Published private(set) var refreshFailed = false
    @Published private(set) var refreshing = false
    @Published private(set) var expanded: Set<String> = []
    @Published private(set) var details: [String: BranchDetails] = [:]
    /// Keyed by repo and branch; read through `summaryState(for:)`.
    @Published private(set) var summaryStates: [String: SummaryState] = [:]
    @Published private(set) var claude: ClaudeLookup = .unknown

    private(set) var isOpen = false
    private let env: Environment
    private var focused: UUID?
    private var lastPwd: String?
    private var location: RepoLocation?
    private var focusGeneration = 0
    private var loading = false
    private var reloadAgain = false
    private var watcher: AnyObject?
    private var phone: [BranchSession] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var phoneTimer: Timer?
    private var runs: [String: RunHandle] = [:]

    init(env: Environment = .live) {
        self.env = env
    }

    var canSummarize: Bool {
        if case .found = claude { return true }
        return false
    }

    // MARK: Opening and focus

    /// Starts following the window's focused pane. The returned task finishes
    /// once that pane's repo is shown (tests wait on it).
    @discardableResult
    func open(focused: UUID?) -> Task<Void, Never> {
        guard !isOpen else { return Task {} }
        isOpen = true
        status = .loading
        env.changes()
            .sink { [weak self] _ in self?.sessionsChanged() }
            .store(in: &subscriptions)
        phoneTimer = Timer.scheduledTimer(withTimeInterval: env.phoneInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPhoneSessions() }
        }
        refreshPhoneSessions()
        Task { await lookUpClaude() }
        return Task { await setFocus(focused) }
    }

    func close() {
        isOpen = false
        focusGeneration += 1
        subscriptions.removeAll()
        phoneTimer?.invalidate()
        phoneTimer = nil
        watcher = nil
        location = nil
        lastPwd = nil
        snapshot = nil
        sections = .empty
        expanded = []
        details = [:]
        refreshFailed = false
        status = .closed
    }

    func focusChanged(_ pane: UUID?) {
        focused = pane
        Task { await setFocus(pane) }
    }

    /// Shows the repo of `pane`. A later call wins over an earlier one
    /// still finding its repo.
    func setFocus(_ pane: UUID?) async {
        guard isOpen else { return }
        focused = pane
        focusGeneration += 1
        let generation = focusGeneration
        guard let pane, let pwd = env.pwd(pane), !pwd.isEmpty else {
            show(location: nil, status: .noPane)
            return
        }
        lastPwd = pwd
        let locate = env.locate
        let found = await Task.detached { locate(pwd) }.value
        guard isOpen, generation == focusGeneration else { return }
        guard let found else {
            show(location: nil, status: .notARepo)
            return
        }
        guard found != location else { return }
        show(location: found, status: .loading)
        watcher = env.watch(found.commonDir) { [weak self] changes in self?.repoChanged(changes) }
        await reload()
    }

    private func show(location: RepoLocation?, status: Status) {
        if location != self.location {
            watcher = nil
            snapshot = nil
            sections = .empty
            expanded = []
            details = [:]
            refreshFailed = false
        }
        self.location = location
        self.status = status
    }

    // MARK: Reading the repo

    /// Re-reads the current repo. A call while a read runs makes that read
    /// go again when it finishes, so a burst of changes costs two reads.
    func reload() async {
        guard location != nil else { return }
        if loading {
            reloadAgain = true
            return
        }
        loading = true
        refreshing = true
        defer {
            loading = false
            refreshing = false
        }
        repeat {
            reloadAgain = false
            guard let target = location else { break }
            let read = env.read
            let now = env.now()
            let result = await Task.detached { read(target, now) }.value
            guard location == target else {
                reloadAgain = true
                continue
            }
            if let result {
                snapshot = result
                refreshFailed = false
                status = .loaded
                rebuildSections()
                for name in expanded { Task { await loadDetails(name) } }
            } else if snapshot == nil {
                status = .failed
            } else {
                refreshFailed = true
            }
        } while reloadAgain
    }

    private func repoChanged(_ changes: Set<RepoWatcher.Change>) {
        if changes.contains(.refs) {
            Task { await reload() }
        } else {
            for name in expanded { Task { await loadDetails(name) } }
        }
    }

    private func sessionsChanged() {
        guard isOpen else { return }
        if let focused, env.pwd(focused) != lastPwd {
            // Read the focus when the task runs, so a focus change queued
            // meanwhile isn't overridden by this older one.
            Task { [weak self] in
                guard let self, let current = self.focused else { return }
                await self.setFocus(current)
            }
        }
        rebuildSections()
    }

    private func refreshPhoneSessions() {
        let fetch = env.phoneSessions
        Task {
            let sessions = await Task.detached { fetch() }.value
            guard isOpen, sessions != phone else { return }
            phone = sessions
            rebuildSections()
        }
    }

    private func rebuildSections() {
        guard let snapshot else {
            sections = .empty
            return
        }
        let placement = SessionPlacement.assign(env.panes() + phone, worktrees: snapshot.worktrees)
        sections = BranchSections.build(snapshot, placement: placement, now: env.now())
    }

    // MARK: Rows

    func toggle(_ name: String) {
        if expanded.remove(name) == nil {
            expanded.insert(name)
            Task { await loadDetails(name) }
        }
    }

    func loadDetails(_ name: String) async {
        guard let snapshot, let branch = snapshot.branches.first(where: { $0.name == name }) else { return }
        let tree = snapshot.worktrees.first { $0.branch == name }
        let read = env.details
        let base = snapshot.base
        let root = snapshot.root
        let result = await Task.detached { read(branch, base, tree, root) }.value
        guard self.snapshot?.root == root else { return }
        details[name] = result
    }

    // MARK: Summaries

    func lookUpClaude() async {
        guard claude == .unknown else { return }
        let locate = env.locateClaude
        let path = await Task.detached { locate() }.value
        claude = path.map(ClaudeLookup.found) ?? .missing
    }

    private func runKey(_ commonDir: String, _ name: String) -> String {
        "\(commonDir)\n\(name)"
    }

    /// The summary state of `name` in the repo showing now.
    func summaryState(for name: String) -> SummaryState? {
        guard let snapshot else { return nil }
        return summaryStates[runKey(snapshot.commonDir, name)]
    }

    func summary(for name: String) -> BranchSummary? {
        guard let snapshot else { return nil }
        return env.cache.summary(repo: snapshot.commonDir, branch: name)
    }

    func summarize(_ name: String) {
        Task { await summarizeNow(name) }
    }

    func summarizeNow(_ name: String) async {
        guard case .found(let claude) = claude, let snapshot, let base = snapshot.base, name != base,
              let branch = snapshot.branches.first(where: { $0.name == name }),
              summaryStates[runKey(snapshot.commonDir, name)] != .running else { return }
        let key = runKey(snapshot.commonDir, name)
        let handle = RunHandle()
        runs[key] = handle
        summaryStates[key] = .running
        let run = env.summarize
        let root = snapshot.root
        let result = await Task.detached { run(name, base, root, claude, handle) }.value
        guard runs[key] === handle else { return }
        runs[key] = nil
        switch result {
        case .success(let text):
            env.cache.store(
                BranchSummary(tip: branch.tip, text: text, createdAt: env.now()),
                repo: snapshot.commonDir, branch: name)
            summaryStates[key] = nil
        case .failure(.cancelled):
            summaryStates[key] = nil
        case .failure(let error):
            summaryStates[key] = .failed(error.message)
        }
    }

    func cancelSummary(_ name: String) {
        guard let snapshot else { return }
        runs[runKey(snapshot.commonDir, name)]?.cancel()
    }
}
#endif
