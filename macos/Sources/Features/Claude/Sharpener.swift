#if os(macOS)
import AppKit

/// Lostty's prompt sharpener: a Claude Code mod each pane loads, which
/// rewrites a sloppy prompt before Claude reads it and logs every prompt
/// through `+sharpen-log`. The app loads the mod, shows the latest rewrite
/// under the pane (SharpenStrip), and keeps each pane's switch, off until
/// turned on from the bottom bar.
/// Design: docs/superpowers/specs/2026-11-13-lostty-prompt-sharpener-design.md
enum Sharpener {
    static let pluginDirsKey = "CLAUDE_CODE_PLUGIN_DIRS"

    /// The mod for panes to load: a copy of the bundled one
    /// (`zig-out/share/ghostty/lostty-mods`), made once per launch, because
    /// Claude Code writes type files into a mod's folder, which would break
    /// the app's signature.
    static let modPath: String? = {
        guard let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("ghostty/lostty-mods/lostty-sharpener") else { return nil }
        let copy = folder.deletingLastPathComponent().appendingPathComponent("mods/lostty-sharpener")
        return copyMod(from: bundled, to: copy) ? copy.path : nil
    }()

    /// Replaces `target` with a copy of `source`.
    nonisolated static func copyMod(from source: URL, to target: URL) -> Bool {
        let files = FileManager.default
        guard files.fileExists(atPath: source.path) else { return false }
        try? files.removeItem(at: target)
        do {
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.copyItem(at: source, to: target)
            return true
        } catch {
            return false
        }
    }

    /// `existing` with `mod` added, so a pane keeps the owner's own folders.
    static func pluginDirs(existing: String?, mod: String) -> String {
        let dirs = (existing ?? "").split(separator: ":").map(String.init)
        return (dirs.contains(mod) ? dirs : dirs + [mod]).joined(separator: ":")
    }

    /// Where `+sharpen-log` keeps the log, and the mod looks for each
    /// pane's switch (`on/<pane>`).
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lostty/sharpener")
    }

    /// One rewrite from the log: what was typed, what Claude got, and the
    /// labels for what changed.
    struct Entry: Decodable, Equatable, Sendable {
        let id: String
        let original: String
        let sent: String
        let fixed: [String]?
    }

    /// The entry `id` names in `log`, newest first.
    nonisolated static func entry(id: String, in log: String) -> Entry? {
        for line in log.split(separator: "\n").reversed() where line.contains("\"\(id)\"") {
            if let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)), entry.id == id {
                return entry
            }
        }
        return nil
    }

    /// The entry `id` names, read from the end of the log.
    nonisolated static func readEntry(id: String) -> Entry? {
        let url = folder.appendingPathComponent("log.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let tail: UInt64 = 1 << 20
        try? handle.seek(toOffset: size > tail ? size - tail : 0)
        guard let data = try? handle.readToEnd(), let text = tailText(data, cut: size > tail) else { return nil }
        return entry(id: id, in: text)
    }

    /// The log's last bytes as text. A `cut` tail starts mid-line, maybe
    /// mid-character, so its first line is dropped.
    nonisolated static func tailText(_ data: Data, cut: Bool) -> String? {
        var data = data
        if cut, let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            data = data.subdata(in: data.index(after: newline)..<data.endIndex)
        }
        return String(bytes: data, encoding: .utf8)
    }
}

/// Each pane's switch, and its latest rewrite until its next prompt goes
/// out as typed or its conversation ends.
@MainActor
final class PaneSharpens: ObservableObject {
    static let shared = PaneSharpens(folder: Sharpener.folder)

    @Published private(set) var entries: [UUID: Sharpener.Entry] = [:]
    /// Panes with the switch on. The mod reads one empty file per pane in
    /// `on/`, so a switch holds across Restart to Update.
    @Published private(set) var on: Set<UUID>
    private let onFolder: URL

    init(folder: URL) {
        onFolder = folder.appendingPathComponent("on")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: onFolder.path)) ?? []
        on = Set(names.compactMap(UUID.init(uuidString:)))
    }

    func isOn(_ pane: UUID) -> Bool { on.contains(pane) }

    func setOn(_ isOn: Bool, for pane: UUID) {
        let file = onFolder.appendingPathComponent(pane.uuidString)
        if isOn {
            try? FileManager.default.createDirectory(at: onFolder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: nil)
            on.insert(pane)
        } else {
            try? FileManager.default.removeItem(at: file)
            on.remove(pane)
            clear(pane)
        }
    }

    func show(_ entry: Sharpener.Entry, on pane: UUID) {
        entries[pane] = entry
    }

    func clear(_ pane: UUID) {
        if entries[pane] != nil { entries[pane] = nil }
    }

    /// Reads `id`'s entry off the main thread, then shows it.
    func load(_ id: String, on pane: UUID) {
        Task.detached(priority: .utility) {
            guard let entry = Sharpener.readEntry(id: id) else { return }
            await MainActor.run { PaneSharpens.shared.show(entry, on: pane) }
        }
    }
}
#endif
