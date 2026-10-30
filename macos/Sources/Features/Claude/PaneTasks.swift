#if os(macOS)
import AppKit

/// A subagent or background shell Claude started in a pane, for the strip
/// under the bottom bar (PaneTaskStrip).
struct PaneTask: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable { case subagent, shell }

    let id: String
    let kind: Kind
    /// A subagent's type ("Explore"), or the description Claude gave a
    /// shell ("Start the dev server").
    let title: String
    /// A subagent's transcript, or the shell's output file; nil when the
    /// hook couldn't name it.
    let path: String?

    /// `path` when it may be read. It comes from a user var, which anything
    /// printed in a pane can set: only a subagent's transcript in Claude's
    /// own projects folder, or a shell's `tasks/<id>.output` in Claude's
    /// temporary folder.
    nonisolated func readablePath(
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        user: uid_t = getuid()
    ) -> String? {
        guard let path, path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return nil }
        let file = path as NSString
        let folder = (file.deletingLastPathComponent as NSString).lastPathComponent
        switch kind {
        case .subagent:
            guard file.pathExtension == "jsonl", file.lastPathComponent.hasPrefix("agent-"), folder == "subagents",
                  TranscriptLocation.roots(home: home, environment: environment)
                      .contains(where: { root, agent in agent == .claude && path.hasPrefix(root + "/") }) else { return nil }
        case .shell:
            guard folder == "tasks", file.lastPathComponent == "\(id).output",
                  ["/private/tmp/claude-\(user)/", "/tmp/claude-\(user)/"].contains(where: path.hasPrefix) else { return nil }
        }
        return path
    }
}

/// Each pane's working subagents and background shells, oldest first: the
/// newest `limit`. Each goes when it finishes, and all go when Claude stops
/// with nothing left working, the session ends, or the window is cleared.
@MainActor
final class PaneTasks: ObservableObject {
    static let shared = PaneTasks()
    static let limit = 20

    @Published private(set) var lists: [UUID: [PaneTask]] = [:]

    func apply(_ event: ClaudeMessage.TaskEvent, to pane: UUID) {
        set(pane, Self.updated(lists[pane] ?? [], with: event))
    }

    func clear(_ pane: UUID) {
        set(pane, nil)
    }

    private func set(_ pane: UUID, _ list: [PaneTask]?) {
        let list = list?.isEmpty == true ? nil : list
        if list != lists[pane] { lists[pane] = list }
    }

    /// `list` after `event`: a new task goes last, and the oldest goes past
    /// `limit`; a finished one goes.
    nonisolated static func updated(_ list: [PaneTask], with event: ClaudeMessage.TaskEvent) -> [PaneTask] {
        switch event {
        case .started(let task):
            guard !list.contains(where: { $0.id == task.id }) else { return list }
            return Array((list + [task]).suffix(limit))
        case .finished(let id):
            return list.filter { $0.id != id }
        }
    }
}
#endif
