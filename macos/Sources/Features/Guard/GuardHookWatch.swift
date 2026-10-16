#if os(macOS)
import Foundation

enum GuardHealth {
    /// Agents whose guard was installed before and isn't now: the ones to flag.
    static func newlyDisconnected(previous: [HookAgent: ClaudeHooksStatus], current: [HookAgent: ClaudeHooksStatus]) -> Set<HookAgent> {
        Set(current.compactMap { agent, status in
            previous[agent] == .installed && status != .installed ? agent : nil
        })
    }

    /// Every agent whose hooks aren't fully installed, among those present.
    static func disconnected(_ current: [HookAgent: ClaudeHooksStatus]) -> Set<HookAgent> {
        Set(current.compactMap { $0.value == .installed ? nil : $0.key })
    }
}

extension GuardHealth {
    /// Folds a fresh round of checks into the previous statuses. A nil means
    /// the check itself failed to run, which says nothing about the hooks, so
    /// the previous status stands (and an agent never seen is omitted).
    static func merge(previous: [HookAgent: ClaudeHooksStatus], fresh: [HookAgent: ClaudeHooksStatus?]) -> [HookAgent: ClaudeHooksStatus] {
        var out: [HookAgent: ClaudeHooksStatus] = [:]
        for (agent, status) in fresh {
            if let status { out[agent] = status } else if let old = previous[agent] { out[agent] = old }
        }
        return out
    }
}

extension HookAgent {
    /// The file the agent reads its hooks from, inside `configDirectory`.
    var hooksFile: String {
        switch self {
        case .claude: "settings.json"
        case .codex: "hooks.json"
        }
    }
}

/// Watches the agents' settings folders and files, so a guard hook that
/// disappears (an agent editing its own settings, a dotfile sync) shows at
/// once (spec §7.6). The folder catches renames and creations (the CLI and
/// most editors replace these files by rename); the file itself catches
/// in-place writes, and is re-armed after a rename or delete, as
/// SkinConfigStore does.
@MainActor
final class GuardHookWatch {
    private let onChange: @MainActor () -> Void
    private var dirSources: [DispatchSourceFileSystemObject] = []
    private var fileSources: [HookAgent: DispatchSourceFileSystemObject] = [:]
    private var pending: DispatchWorkItem?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        stop()
        let home = FileManager.default.homeDirectoryForCurrentUser
        for agent in HookAgent.allCases {
            let dir = home.appendingPathComponent(agent.configDirectory)
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.schedule()
                    self?.armFileWatcher(agent)
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            dirSources.append(source)
            armFileWatcher(agent)
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        dirSources.forEach { $0.cancel() }
        dirSources.removeAll()
        fileSources.values.forEach { $0.cancel() }
        fileSources.removeAll()
    }

    /// Opens a watcher on the agent's settings file if none is armed and the
    /// file exists; the folder watcher re-arms it when the file reappears.
    private func armFileWatcher(_ agent: HookAgent) {
        guard fileSources[agent] == nil else { return }
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(agent.configDirectory)
            .appendingPathComponent(agent.hooksFile).path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                self?.schedule()
                guard let source, source.data.contains(.delete) || source.data.contains(.rename) else { return }
                self?.fileSources[agent]?.cancel()
                self?.fileSources[agent] = nil
                self?.armFileWatcher(agent)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSources[agent] = source
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.onChange() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
#endif
