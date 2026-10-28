#if os(macOS)
import Foundation

/// The names Claude Code gives its running sessions, which its agents use
/// for each other (ListAgents, cross-session messages), by the tmux session
/// each runs in. Claude Code writes one file per session,
/// `~/.claude/sessions/<pid>.json`, with `"tmux": "zones-2:@50.%50"` and
/// `"name": "zones-f9"`.
enum ClaudeSessionNames {
    private struct File: Decodable {
        var pid: Int32
        var tmux: String?
        var name: String?
        var updatedAt: Double?
    }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
    }

    /// Each tmux session's name to its Claude's, from the files' contents,
    /// keeping the files of processes still `alive`; where two name one tmux
    /// session, the one updated last.
    static func names(_ files: [Data], alive: (Int32) -> Bool) -> [String: String] {
        let decoder = JSONDecoder()
        var latest: [String: (name: String, at: Double)] = [:]
        for data in files {
            guard let file = try? decoder.decode(File.self, from: data),
                  let tmux = file.tmux, let name = file.name, !name.isEmpty, alive(file.pid),
                  let session = tmux.split(separator: ":").first.map(String.init), !session.isEmpty else { continue }
            let at = file.updatedAt ?? 0
            if let old = latest[session], old.at > at { continue }
            latest[session] = (name, at)
        }
        return latest.mapValues(\.name)
    }

    /// `names` from the files on disk now. Reads files: off the main thread.
    static func read() -> [String: String] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let files = urls.filter { $0.pathExtension == "json" }.compactMap { try? Data(contentsOf: $0) }
        return names(files) { kill($0, 0) == 0 }
    }
}
#endif
