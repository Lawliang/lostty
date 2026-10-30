#if os(macOS)
import Foundation

enum ClaudeConstants {
    /// The user var `+claude-state` sets (spec §2.1).
    static let userVarName = "LOSTTY_CLAUDE"
    /// Set on every pane; the hooks' "inside Lostty?" guard.
    static let surfaceEnvKey = "LOSTTY_SURFACE"
    /// Absolute path of the running Lostty binary, for the hooks to call.
    static let binEnvKey = "LOSTTY_BIN"
}

/// What a Claude Code hook reports through `+claude-state`. `agents`:
/// Claude finished its turn but its subagents are still working, so it
/// carries on by itself. `resumed`: the last of them finished, so Claude
/// itself works again.
enum ClaudeState: String {
    case busy, idle, exit, agents, resumed
}

enum ClaudeMessage {
    /// Decodes a LOSTTY_CLAUDE value, `{"v":1,"state":"…"}`. The core has
    /// already base64-decoded it (Surface.decodeUserVar). Other versions,
    /// unknown states and malformed input decode to nil.
    static func decode(_ value: String) -> ClaudeState? {
        guard let raw = object(value)?["state"] as? String else { return nil }
        return ClaudeState(rawValue: raw)
    }

    /// What a tool call is about to do, from a PreToolUse hook's
    /// `{"v":1,"state":"tool","action":"Editing Foo.swift"}`; nil for
    /// anything else.
    static func action(_ value: String) -> String? {
        guard let object = object(value), object["state"] as? String == "tool",
              let action = object["action"] as? String, !action.isEmpty else { return nil }
        return action
    }

    /// The agent a SendMessage was for, when the hook kept it inside the
    /// pane's zone: `{"v":1,"state":"tool","action":"SendMessage","denied":"name"}`.
    static func denied(_ value: String) -> String? {
        guard let object = object(value), object["state"] as? String == "tool",
              let target = object["denied"] as? String, !target.isEmpty else { return nil }
        return target
    }

    /// An `idle` that is Claude asking permission (`"permission":true`) to
    /// run the last action, rather than finishing its turn.
    static func isPermission(_ value: String) -> Bool {
        object(value)?["permission"] as? Bool == true
    }

    /// The conversation file an `idle` names (`"transcript":"…"`), for the
    /// turn observer; nil for anything else. Only a hint: anything in a pane
    /// can print this user var, so TranscriptLocation decides what is read.
    static func transcript(_ value: String) -> String? {
        guard let object = object(value), object["state"] as? String == "idle",
              let path = object["transcript"] as? String, !path.isEmpty else { return nil }
        return path
    }

    /// Which agent sent this, when the message says: only Claude's hooks
    /// send `tool`, `agents` and `resumed`, and an `idle` names its
    /// transcript, which lives under the agent's own folder. Nil when it
    /// can't tell (a `busy` comes from either).
    static func agentKind(_ value: String) -> HookAgent? {
        guard let object = object(value), let state = object["state"] as? String else { return nil }
        switch state {
        case "tool", "agents", "resumed":
            return .claude
        case "idle":
            guard let path = object["transcript"] as? String else { return nil }
            if path.contains("/.codex/") { return .codex }
            if path.contains("/.claude/") { return .claude }
            return nil
        default:
            return nil
        }
    }

    /// `{"v":1,"state":"fresh"}`: a fresh window's start hook took the
    /// context handoff after /clear. Not a ClaudeState: it changes no phase.
    static func isFresh(_ value: String) -> Bool {
        object(value)?["state"] as? String == "fresh"
    }

    /// `{"v":1,"state":"cleared"}`: the window was cleared with no handoff
    /// waiting (your own /clear). Not a ClaudeState either.
    static func isCleared(_ value: String) -> Bool {
        object(value)?["state"] as? String == "cleared"
    }

    /// A subagent starting (`subagent`) or finishing (`subagent_done`),
    /// from the SubagentStart and SubagentStop hooks, or a background shell
    /// starting (`shell`, PostToolUse) or finishing (`shell_done`, Claude
    /// Code's task notification); nil for anything else. Not a ClaudeState:
    /// it changes no phase.
    static func task(_ value: String) -> TaskEvent? {
        guard let object = object(value), let state = object["state"] as? String else { return nil }
        switch state {
        case "subagent", "subagent_done":
            guard let agent = object["agent"] as? [String: Any],
                  let id = agent["id"] as? String, !id.isEmpty,
                  let type = agent["type"] as? String, !type.isEmpty,
                  let transcript = agent["transcript"] as? String, !transcript.isEmpty else { return nil }
            let task = PaneTask(id: id, kind: .subagent, title: type, path: transcript)
            return state == "subagent" ? .started(task) : .stopped(task)
        case "shell":
            guard let shell = object["shell"] as? [String: Any], let id = shell["id"] as? String, !id.isEmpty else { return nil }
            let title = (shell["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Shell"
            return .started(PaneTask(id: id, kind: .shell, title: title, path: shell["output"] as? String))
        case "shell_done":
            guard let id = (object["shell"] as? [String: Any])?["id"] as? String, !id.isEmpty else { return nil }
            return .finished(id)
        default:
            return nil
        }
    }

    enum TaskEvent: Equatable {
        case started(PaneTask)
        case stopped(PaneTask)
        /// A background task finished, by id.
        case finished(String)
    }

    /// A `busy` for a prompt the owner typed (`"typed":true`), not Claude
    /// Code's notice that background tasks finished.
    static func isTyped(_ value: String) -> Bool {
        object(value)?["typed"] as? Bool == true
    }

    private static func object(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (object["v"] as? Int) == 1 else { return nil }
        return object
    }
}
#endif
