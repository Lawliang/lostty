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

    private static func object(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (object["v"] as? Int) == 1 else { return nil }
        return object
    }
}
#endif
