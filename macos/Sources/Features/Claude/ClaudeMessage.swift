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

/// What a Claude Code hook reports through `+claude-state`.
enum ClaudeState: String {
    case busy, idle, exit
}

enum ClaudeMessage {
    /// Decodes a LOSTTY_CLAUDE value: base64 of `{"v":1,"state":"…"}`.
    /// Other versions, unknown states and malformed input decode to nil.
    static func decode(_ value: String) -> ClaudeState? {
        guard let data = Data(base64Encoded: value),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (object["v"] as? Int) == 1,
              let raw = object["state"] as? String else { return nil }
        return ClaudeState(rawValue: raw)
    }
}
#endif
