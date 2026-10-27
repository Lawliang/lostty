#if os(macOS)
import Foundation

/// The Claude or Codex conversation a pane was in, so Continue can resume
/// it after the Mac restarts.
struct PaneConversation: Codable, Equatable {
    /// A `HookAgent` raw value.
    var agent: String
    /// The conversation's id: always a UUID (it is typed into a shell).
    var id: String

    /// From the conversation file a turn's end names: Claude's
    /// `~/.claude/projects/…/<id>.jsonl` or Codex's
    /// `~/.codex/sessions/…/rollout-<time>-<id>.jsonl`. Nil for anything
    /// else.
    static func from(transcript path: String) -> PaneConversation? {
        let file = (path as NSString).lastPathComponent
        guard file.hasSuffix(".jsonl") else { return nil }
        let stem = String(file.dropLast(".jsonl".count))
        let agent: HookAgent, id: String
        if path.contains("/.codex/") {
            (agent, id) = (.codex, String(stem.suffix(36)))
        } else if path.contains("/.claude/") {
            (agent, id) = (.claude, stem)
        } else {
            return nil
        }
        guard UUID(uuidString: id) != nil else { return nil }
        return PaneConversation(agent: agent.rawValue, id: id)
    }

    /// What Continue types into the pane's shell; nil for an id that isn't
    /// a UUID or an agent this build doesn't know.
    var resumeCommand: String? {
        guard UUID(uuidString: id) != nil else { return nil }
        switch HookAgent(rawValue: agent) {
        case .claude: return "claude --resume \(id)"
        case .codex: return "codex resume \(id)"
        case nil: return nil
        }
    }
}

/// Lostty as it last was: every window and the canvas (`WindowSnapshot`),
/// each pane's id, and the conversation each agent pane was in. Kept up to
/// date while Lostty runs (`LastSessionStore`); when the Mac restarts (or
/// Lostty ends other than by your quitting it) and the panes' tmux sessions
/// end with it, the next Lostty offers to continue it (`SessionRestore`).
/// Quitting it yourself leaves it in the history only. One file per build
/// (bundle id).
struct LastSession: Codable, Equatable {
    var at: Date
    var windows: WindowSnapshot
    /// Every pane's id: whether any one's tmux session is still running
    /// tells a crash (the sessions live on) from a restart or a quit.
    var panes: [String]
    /// The agent panes' conversations, by pane id.
    var conversations: [String: PaneConversation]

    static func url(bundleID: String, in folder: URL) -> URL {
        folder.appendingPathComponent("last-session-\(bundleID).json")
    }

    static var standardURL: URL {
        url(
            bundleID: Bundle.main.bundleIdentifier ?? "com.lawliang.lostty",
            in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lostty", isDirectory: true))
    }

    /// Over: none of its panes' tmux sessions is running, so the Mac
    /// restarted or Lostty quit and ended them. With one running, Lostty
    /// crashed, and the crash's own "Reopen?" applies.
    func isOver(liveSurfaces: Set<String>) -> Bool {
        !panes.isEmpty && panes.allSatisfy { !liveSurfaces.contains($0) }
    }

    /// "3 windows and the canvas · 9 terminals · 4 Claude conversations".
    var summary: String {
        let windowCount = windows.groups.filter { $0.canvas == nil }.count
        let hasCanvas = windows.groups.contains { $0.canvas != nil }
        var place = [Self.count(windowCount, "window")]
        if windowCount == 0 { place = [] }
        if hasCanvas { place.append("the canvas") }
        var parts = [place.joined(separator: " and "), Self.count(panes.count, "terminal")]
        if !conversations.isEmpty {
            let agents = Set(conversations.values.map(\.agent))
            let name = agents.count == 1 ? HookAgent(rawValue: agents.first ?? "")?.title ?? "agent" : "agent"
            parts.append(Self.count(conversations.count, "\(name) conversation"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// The same session, ignoring when it was saved: whether a save would
    /// change anything.
    func sameContents(as other: LastSession) -> Bool {
        windows == other.windows && panes == other.panes && conversations == other.conversations
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func load(from url: URL) -> LastSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(LastSession.self, from: data)
    }

    static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
