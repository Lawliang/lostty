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

    /// What a path inside the git dir means for the panel. An allowlist of
    /// what it shows: branch refs, HEADs, worktrees coming and going, rebase
    /// state, and the staging area. Everything else (objects, reflogs, lock
    /// files, FETCH_HEAD, fsmonitor cookies, submodules…) is nil, so the
    /// panel's own `git status` can't set off another read.
    /// Judged by the path inside `gitDir`, so folders above it can't matter.
    static func classify(_ path: String, gitDir: String) -> Change? {
        classify(path, roots: roots(of: gitDir))
    }

    /// `gitDir` as given and with symlinks resolved; event paths may use either.
    static func roots(of gitDir: String) -> [String] {
        let canonical = URL(fileURLWithPath: gitDir).resolvingSymlinksInPath().path
        return canonical == gitDir ? [gitDir] : [gitDir, canonical]
    }

    static func classify(_ path: String, roots: [String]) -> Change? {
        guard let relative = relativePath(path, roots: roots) else { return nil }
        let parts = relative.split(separator: "/").map(String.init)
        guard let name = parts.last, !name.hasSuffix(".lock") else { return nil }
        if parts.first == "refs" { return .refs }
        if parts.count == 2, parts[0] == "worktrees" { return .refs }
        // The rest is per checkout: at the top for the main one, under
        // worktrees/<name>/ for a linked one.
        let local = parts.count > 2 && parts[0] == "worktrees" ? Array(parts.dropFirst(2)) : parts
        switch local {
        case ["HEAD"]: return .refs
        case ["packed-refs"]: return parts.count == 1 ? .refs : nil
        case ["index"]: return .index
        case ["rebase-merge"], ["rebase-apply"], ["rebase-merge", "head-name"], ["rebase-apply", "head-name"]:
            return .refs
        default: return nil
        }
    }

    private static func relativePath(_ path: String, roots: [String]) -> String? {
        for root in roots {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        }
        guard let canonical = roots.last else { return nil }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let prefix = canonical + "/"
        return resolved.hasPrefix(prefix) ? String(resolved.dropFirst(prefix.count)) : nil
    }

    /// The watched dir as given and canonical, worked out once.
    private let roots: [String]
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor (Set<Change>) -> Void

    init?(gitDir: String, latency: TimeInterval = 0.3, onChange: @escaping @MainActor (Set<Change>) -> Void) {
        self.onChange = onChange
        self.roots = RepoWatcher.roots(of: gitDir)
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            let changes = Set(list.compactMap { RepoWatcher.classify($0, roots: watcher.roots) })
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
