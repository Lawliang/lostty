#if os(macOS)
import CoreServices
import Foundation

/// Watches a repo's shared git directory (refs, HEAD, every worktree's
/// HEAD and index) while the Branches panel is open. Events are coalesced
/// over `latency`. Stops when released.
final class RepoWatcher {
    enum Change: Hashable {
        /// Branches, HEADs or rebase state moved: re-read the repo.
        case refs
        /// Only the staging area changed: refresh uncommitted-change counts.
        case index
    }

    /// nil for churn the panel doesn't show (objects, reflogs, lock files).
    static func classify(_ path: String) -> Change? {
        let name = (path as NSString).lastPathComponent
        if path.contains("/objects/") || path.contains("/logs/") || name.hasSuffix(".lock") { return nil }
        return name == "index" ? .index : .refs
    }

    private var stream: FSEventStreamRef?
    private let onChange: @MainActor (Set<Change>) -> Void

    init?(gitDir: String, latency: TimeInterval = 0.3, onChange: @escaping @MainActor (Set<Change>) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            let changes = Set(list.compactMap(RepoWatcher.classify))
            guard !changes.isEmpty else { return }
            MainActor.assumeIsolated { watcher.onChange(changes) }
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [gitDir] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
#endif
