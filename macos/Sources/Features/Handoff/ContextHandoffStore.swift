#if os(macOS)
import Foundation

/// A pane's handoff as the coordinator holds it, saved so a Restart to
/// Update picks it up again (spec §4).
struct ContextHandoffPane: Codable, Equatable {
    /// `armed`: waiting for the agent's handoff. `pending`: saved, in the
    /// grace before /clear. `clearing`: /clear typed, waiting for the
    /// fresh window to take the handoff.
    enum Phase: String, Codable { case armed, pending, clearing }

    var phase: Phase
    var level: ContextHandoffLevel
    var byButton: Bool
    /// The context size when the directive was last queued.
    var saidAt: Int
    var used: Int
    var size: Int
    /// The ceiling nudge was typed (once per arming).
    var nudged = false
    /// The saved handoff, while pending or clearing.
    var handoff: String?
    var next: ContextHandoff.Next?
    var summary: String?
}

/// Lostty's handoff files under Application Support (spec §3, §4): each
/// pane's state, the texts its hooks take (`+claude-state`, which reads
/// `handoff/panes/<PANE>.say` and `.start`), the handoff file its agent
/// writes (`.handoff.md`), and the saved handoffs.
struct ContextHandoffStore: Sendable {
    static let standard = ContextHandoffStore(root: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lostty"))
    static let keep = 50

    let root: URL

    var panes: URL { root.appendingPathComponent("handoff/panes") }
    var handoffs: URL { root.appendingPathComponent("handoffs") }

    private func file(_ pane: UUID, _ ext: String) -> URL {
        panes.appendingPathComponent("\(pane.uuidString).\(ext)")
    }

    private func write(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The directive the next prompt or tool call gives Claude.
    func writeSay(_ pane: UUID, _ text: String) { write(text, to: file(pane, "say")) }
    /// The handoff the fresh window's start hook gives Claude.
    func writeStart(_ pane: UUID, _ text: String) { write(text, to: file(pane, "start")) }
    func removeSay(_ pane: UUID) { try? FileManager.default.removeItem(at: file(pane, "say")) }

    /// Where the directive tells the pane's agent to write its handoff.
    func handoffFile(_ pane: UUID) -> URL { file(pane, "handoff.md") }

    /// The handoff file's text, removing it (a later handoff is a new
    /// file, which Claude's Write tool makes without reading first). Nil
    /// when there is none.
    func takeHandoffFile(_ pane: UUID) -> String? {
        let url = handoffFile(pane)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return text
    }

    func removeHandoffFile(_ pane: UUID) { try? FileManager.default.removeItem(at: handoffFile(pane)) }

    func saveState(_ pane: UUID, _ state: ContextHandoffPane) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: panes, withIntermediateDirectories: true)
        try? data.write(to: file(pane, "json"), options: .atomic)
    }

    func loadStates() -> [UUID: ContextHandoffPane] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: panes.path)) ?? []
        var result: [UUID: ContextHandoffPane] = [:]
        for name in names where name.hasSuffix(".json") {
            guard let pane = UUID(uuidString: String(name.dropLast(5))),
                  let data = try? Data(contentsOf: panes.appendingPathComponent(name)),
                  let state = try? JSONDecoder().decode(ContextHandoffPane.self, from: data) else { continue }
            result[pane] = state
        }
        return result
    }

    /// The pane's state, both hook texts and any handoff file.
    func removeAll(_ pane: UUID) {
        for ext in ["json", "say", "start", "handoff.md"] { try? FileManager.default.removeItem(at: file(pane, ext)) }
    }

    /// Saves a handoff as `handoffs/<project>/<yyyy-MM-dd HHmm>.md` (with
    /// " 2", " 3"… when that minute is taken) and keeps the newest 50.
    func saveHandoff(_ text: String, project: String, at date: Date) throws -> URL {
        let safe = project.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let dir = handoffs.appendingPathComponent(safe.isEmpty ? "Terminal" : safe)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let stem = formatter.string(from: date)
        var url = dir.appendingPathComponent("\(stem).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(stem) \(n).md")
            n += 1
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        prune(dir)
        return url
    }

    private func prune(_ dir: URL) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "md" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
            }
        for url in files.dropLast(Self.keep) { try? fm.removeItem(at: url) }
    }
}
#endif
