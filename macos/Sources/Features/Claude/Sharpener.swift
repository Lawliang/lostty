#if os(macOS)
import AppKit

/// Lostty's prompt sharpener: a Claude Code mod each pane loads, which
/// rewrites a sloppy prompt before Claude reads it and logs every prompt
/// through `+sharpen-log`. The app loads the mod, shows the latest rewrite
/// under the pane (SharpenStrip), and keeps the off switch.
/// Design: docs/superpowers/specs/2026-11-13-lostty-prompt-sharpener-design.md
enum Sharpener {
    static let pluginDirsKey = "CLAUDE_CODE_PLUGIN_DIRS"

    /// The bundled mod (`zig-out/share/ghostty/lostty-mods`).
    static var modPath: String? {
        Bundle.main.resourceURL?.appendingPathComponent("ghostty/lostty-mods/lostty-sharpener").path
    }

    /// `existing` with `mod` added, so a pane keeps the owner's own folders.
    static func pluginDirs(existing: String?, mod: String) -> String {
        let dirs = (existing ?? "").split(separator: ":").map(String.init)
        return (dirs.contains(mod) ? dirs : dirs + [mod]).joined(separator: ":")
    }

    /// Where `+sharpen-log` keeps the log, and the mod looks for `off`.
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lostty/sharpener")
    }

    static var isOn: Bool {
        get { !FileManager.default.fileExists(atPath: folder.appendingPathComponent("off").path) }
        set {
            let off = folder.appendingPathComponent("off")
            if newValue {
                try? FileManager.default.removeItem(at: off)
            } else {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: off.path, contents: nil)
            }
        }
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
        guard let data = try? handle.readToEnd(), let text = String(bytes: data, encoding: .utf8) else { return nil }
        return entry(id: id, in: text)
    }
}

/// Each pane's latest rewrite, until its next prompt goes out as typed or
/// its conversation ends.
@MainActor
final class PaneSharpens: ObservableObject {
    static let shared = PaneSharpens()

    @Published private(set) var entries: [UUID: Sharpener.Entry] = [:]

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
