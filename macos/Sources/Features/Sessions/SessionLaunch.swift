#if os(macOS)
import Foundation

/// The command a new pane runs so its shell lives in a session on Lostty's
/// tmux (`+tmux-launch`, src/cli/tmux_launch.zig).
enum SessionLaunch {
    static let action = "+tmux-launch"

    /// The core runs a pane's command through a shell, so every argument is
    /// single-quoted.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The command for a new pane, or nil to leave the pane alone: a pane
    /// that already has a command (scripts, `-e`, Open Session) keeps it,
    /// and so does every pane while tmux sessions are turned off.
    static func command(existing: String?, binary: String?, disabled: Bool) -> String? {
        guard !disabled, (existing ?? "").isEmpty, let binary, !binary.isEmpty else { return nil }
        return "\(shellQuote(binary)) \(action)"
    }

    /// The command for a window that adopts session `sessionID` ("$3").
    static func attachCommand(binary: String, sessionID: String) -> String {
        "\(shellQuote(binary)) \(action) \(shellQuote("--attach=\(sessionID)"))"
    }

    /// True for commands built here: the pane lives in a tmux session.
    static func isLauncher(_ command: String?) -> Bool {
        command?.contains("' \(action)") ?? false
    }
}
#endif
