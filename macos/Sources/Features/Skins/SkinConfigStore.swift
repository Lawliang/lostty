#if os(macOS)
import Foundation

/// Loads skins.toml, keeps the last good config on errors, and watches for saves.
final class SkinConfigStore {
    let fileURL: URL
    private let home: String
    private(set) var config: SkinConfig = .empty
    private(set) var error: String?
    var onChange: (() -> Void)?
    private var watcher: DispatchSourceFileSystemObject?

    init(fileURL: URL, home: String = NSHomeDirectory()) {
        self.fileURL = fileURL
        self.home = home
    }

    deinit {
        watcher?.cancel()
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

    /// Watches the directory (not the file) so rename-on-save editors are seen.
    func startWatching() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
#endif
