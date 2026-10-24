#if os(macOS)
import AppKit

/// A subagent Claude started in a pane (the SubagentStart hook), for the
/// bottom bar's list. `+agent-watch` follows its transcript.
struct PaneSubagent: Equatable, Identifiable {
    let id: String
    /// "Explore", "general-purpose", a custom agent's name.
    let type: String
    let transcript: String
    var done = false

    /// Its task as Claude worded it, from the `agent-<id>.meta.json`
    /// Claude Code writes beside the transcript; nil until it's there.
    func task() -> String? {
        guard transcript.hasSuffix(".jsonl") else { return nil }
        let meta = String(transcript.dropLast(".jsonl".count)) + ".meta.json"
        guard let data = FileManager.default.contents(atPath: meta),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let task = object["description"] as? String, !task.isEmpty else { return nil }
        return task
    }
}

/// Each pane's subagents in its Claude session, oldest first: the newest
/// `limit`, running or done, so a finished one can still be read back.
/// Cleared when the session ends or the window is cleared.
@MainActor
final class PaneSubagents: ObservableObject {
    static let shared = PaneSubagents()
    static let limit = 20

    @Published private(set) var lists: [UUID: [PaneSubagent]] = [:]

    func apply(_ event: ClaudeMessage.SubagentEvent, to pane: UUID) {
        let list = Self.updated(lists[pane] ?? [], with: event)
        if list != lists[pane] { lists[pane] = list }
    }

    func clear(_ pane: UUID) {
        if lists[pane] != nil { lists[pane] = nil }
    }

    /// `list` after `event`: a new subagent goes last, and the oldest goes
    /// past `limit`; a finished one is marked done, or added done if its
    /// start was missed (the app started after it).
    nonisolated static func updated(_ list: [PaneSubagent], with event: ClaudeMessage.SubagentEvent) -> [PaneSubagent] {
        var list = list
        switch event {
        case .started(let agent):
            guard !list.contains(where: { $0.id == agent.id }) else { return list }
            list.append(agent)
        case .stopped(let agent):
            if let index = list.firstIndex(where: { $0.id == agent.id }) {
                list[index].done = true
                return list
            }
            var done = agent
            done.done = true
            list.append(done)
        }
        return Array(list.suffix(limit))
    }
}

/// A subagent's read-only pane: `lostty +agent-watch` on its transcript,
/// beside the pane whose Claude started it. On the canvas it's a card
/// beside that pane's card; in a window, a split to its right.
@MainActor
enum SubagentPane {
    static func open(_ agent: PaneSubagent, beside pane: UUID) {
        guard allowed(agent.transcript), let binary = Bundle.main.executableURL?.path,
              let view = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: pane) else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.command = command(binary: binary, transcript: agent.transcript)
        config.workingDirectory = view.pwd
        // A transcript it can't read says so, rather than the pane vanishing.
        config.waitAfterCommand = true
        if let canvas = CanvasController.shared, let card = canvas.card(holding: view) {
            canvas.newCard(beside: card, baseConfig: config)
        } else if let controller = view.window?.windowController as? BaseTerminalController {
            _ = controller.newSplit(at: view, direction: .right, baseConfig: config)
        }
    }

    nonisolated static func command(binary: String, transcript: String) -> String {
        "\(SessionLaunch.shellQuote(binary)) +agent-watch \(SessionLaunch.shellQuote(transcript))"
    }

    /// Only a subagent's transcript in Claude's own projects folder: the
    /// path comes from a user var, which anything printed in a pane can set.
    nonisolated static func allowed(
        _ path: String,
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let file = path as NSString
        guard path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              file.pathExtension == "jsonl", file.lastPathComponent.hasPrefix("agent-"),
              (file.deletingLastPathComponent as NSString).lastPathComponent == "subagents" else { return false }
        return TranscriptLocation.roots(home: home, environment: environment)
            .contains { root, agent in agent == .claude && path.hasPrefix(root + "/") }
    }
}
#endif
