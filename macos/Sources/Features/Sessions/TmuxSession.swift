#if os(macOS)
import Foundation

/// Lostty's private tmux (`tmux -L lostty`). Each pane's shell lives in its
/// own session there, so it outlives the window and can be opened from the
/// phone. `+tmux-launch` (src/cli/tmux_launch.zig) creates and tags the
/// sessions; the Mac app lists, adopts and ends them.
enum TmuxConstants {
    static let socket = "lostty"
    static let surfaceOption = "@lostty_surface"
    static let ownerOption = "@lostty_owner"
    static let shellOption = "@lostty_shell"
    /// Set on every pane so the launcher can tag its session with this
    /// Lostty's pid.
    static let appPIDEnvKey = "LOSTTY_APP_PID"
    /// Debug escape hatch: true in `UserDefaults.ghostty` makes new panes
    /// plain local shells.
    static let disabledDefaultsKey = "LosttyTmuxDisabled"
}

/// A session on Lostty's tmux, as `list-sessions` reports it.
struct TmuxSession: Equatable, Sendable {
    var id: String
    var name: String
    /// The pane (`SurfaceView.id`) showing it on the Mac; nil when none does.
    var surface: String?
    /// Pid of the Lostty that shows it; nil when no Lostty does (made on the
    /// phone, or let go after a crash).
    var owner: Int32?

    static let listFormat = "#{session_id}\t#{session_name}\t#{@lostty_surface}\t#{@lostty_owner}"

    /// Parses `list-sessions -F listFormat`; malformed lines are skipped.
    static func parseList(_ output: String) -> [TmuxSession] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, f[0].hasPrefix("$"), !f[1].isEmpty else { return nil }
            return TmuxSession(id: f[0], name: f[1], surface: f[2].isEmpty ? nil : f[2], owner: Int32(f[3]))
        }
    }
}

/// Who a session belongs to. Several Lostty processes can share the socket
/// (a Debug build next to the app), and a window restored after a crash
/// keeps its pane UUID, so every rule checks the owner too.
enum TmuxOwnership {
    /// Owned by a Lostty that is no longer running: left behind by a crash.
    static func orphans(_ sessions: [TmuxSession], isAlive: (Int32) -> Bool) -> [TmuxSession] {
        sessions.filter { session in session.owner.map { !isAlive($0) } ?? false }
    }

    /// Owned by `pid`: ended when that Lostty quits.
    static func owned(by pid: Int32, in sessions: [TmuxSession]) -> [TmuxSession] {
        sessions.filter { $0.owner == pid }
    }

    /// Shown by no running Lostty: what "Open Session" offers.
    static func available(_ sessions: [TmuxSession], isAlive: (Int32) -> Bool) -> [TmuxSession] {
        sessions.filter { session in session.owner.map { !isAlive($0) } ?? true }
    }

    /// The session(s) showing pane `surface` in Lostty `pid`.
    static func showing(_ surface: UUID, ownedBy pid: Int32, in sessions: [TmuxSession]) -> [TmuxSession] {
        sessions.filter { $0.surface == surface.uuidString && $0.owner == pid }
    }
}

/// A pane on Lostty's tmux, for deciding whether closing its window needs
/// a confirmation.
struct TmuxPane: Equatable {
    var surface: String
    var owner: Int32?
    var command: String
    var shell: String

    static let listFormat = "#{@lostty_surface}\t#{@lostty_owner}\t#{pane_current_command}\t#{@lostty_shell}"

    /// Parses `list-panes -a -F listFormat`; panes no Lostty pane shows are skipped.
    static func parseList(_ output: String) -> [TmuxPane] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, !f[0].isEmpty else { return nil }
            return TmuxPane(surface: f[0], owner: Int32(f[1]), command: f[2], shell: f[3])
        }
    }

    /// Whether pane `surface` of Lostty `pid` runs something other than its
    /// shell. nil when tmux can't tell (no such pane, or no recorded shell);
    /// the caller then keeps the core's answer.
    static func isBusy(_ surface: UUID, ownedBy pid: Int32, panes: [TmuxPane]) -> Bool? {
        let mine = panes.filter { $0.surface == surface.uuidString && $0.owner == pid }
        guard !mine.isEmpty, mine.allSatisfy({ !$0.shell.isEmpty }) else { return nil }
        return mine.contains { $0.command != $0.shell }
    }
}

enum ProcessLiveness {
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
#endif
