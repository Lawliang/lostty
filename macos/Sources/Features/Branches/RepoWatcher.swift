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
    /// Judged by the path inside `gitDir`, so folders above it can't matter.
    static func classify(_ path: String, gitDir: String) -> Change? {
        guard let relative = relativePath(path, in: gitDir) else { return nil }
        let parts = relative.split(separator: "/").map(String.init)
        guard let name = parts.last else { return nil }
        if parts.first == "objects" || parts.first == "logs" || name.hasSuffix(".lock") { return nil }
        if parts.count > 2, parts[0] == "worktrees", parts[2] == "logs" { return nil }
        return name == "index" ? .index : .refs
    }

    private static func relativePath(_ path: String, in gitDir: String) -> String? {
        let canonical = URL(fileURLWithPath: gitDir).resolvingSymlinksInPath().path
        for root in [gitDir, canonical] {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let prefix = canonical + "/"
        return resolved.hasPrefix(prefix) ? String(resolved.dropFirst(prefix.count)) : nil
    }

    private let gitDir: String
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor (Set<Change>) -> Void

    init?(gitDir: String, latency: TimeInterval = 0.3, onChange: @escaping @MainActor (Set<Change>) -> Void) {
        self.onChange = onChange
        self.gitDir = gitDir
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            let changes = Set(list.compactMap { RepoWatcher.classify($0, gitDir: watcher.gitDir) })
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
