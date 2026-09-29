#if os(macOS)
import Foundation

/// Loads skins.toml, keeps the last good config on errors, and watches for saves.
final class SkinConfigStore {
    let fileURL: URL
    private let home: String
    private(set) var config: SkinConfig = .empty
    private(set) var error: String?
    var onChange: (() -> Void)?

    /// Watches the directory (rename-saves, and the file's own creation).
    private var dirWatcher: DispatchSourceFileSystemObject?
    /// Watches the file itself so an in-place rewrite (VS Code/Cursor/nano
    /// truncate-then-write) is seen even though it fires no directory event.
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    /// Coalesces a truncate followed by a write into one reload, so we don't
    /// briefly reload against an empty file.
    private static let debounceInterval: TimeInterval = 0.1

    init(fileURL: URL, home: String = NSHomeDirectory()) {
        self.fileURL = fileURL
        self.home = home
    }

    deinit {
        dirWatcher?.cancel()
        fileWatcher?.cancel()
        pendingReload?.cancel()
    }

    func reload() {
        defer { onChange?() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            config = .empty
            error = nil
            return
        }
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            config = try SkinConfig.parse(text, home: home)
            error = nil
        } catch {
            // Keep the last good config; surface the problem to the UI.
            self.error = String(describing: error)
        }
    }

    /// Watches the directory (for rename-saves and the file's creation) AND
    /// the file itself (for editors that rewrite it in place). Idempotent:
    /// cancels any existing sources first, so it is safe to call again, e.g.
    /// to re-arm after the file watcher's target was deleted or replaced.
    func startWatching() {
        dirWatcher?.cancel()
        dirWatcher = nil
        fileWatcher?.cancel()
        fileWatcher = nil

        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dirFD = open(dir.path, O_EVTONLY)
        if dirFD >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: dirFD, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                self?.scheduleReload()
                // The file may have just appeared (created, or replaced by a
                // rename-save); make sure it has a watcher.
                self?.armFileWatcher()
            }
            source.setCancelHandler { close(dirFD) }
            source.resume()
            dirWatcher = source
        }
        armFileWatcher()
    }

    /// Opens a watcher on `fileURL` itself, if one isn't already armed and
    /// the file exists. No-op otherwise; the directory watcher re-arms this
    /// once the file (re)appears.
    private func armFileWatcher() {
        guard fileWatcher == nil else { return }
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            self?.scheduleReload()
            // A delete/rename means this fd's inode is on its way out (an
            // atomic-replace editor just swapped in a new file at this
            // path); drop it and try to re-open the path so the next
            // in-place write is still observed.
            guard let source, source.data.contains(.delete) || source.data.contains(.rename) else { return }
            self?.fileWatcher?.cancel()
            self?.fileWatcher = nil
            self?.armFileWatcher()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }
}
#endif
