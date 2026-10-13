#if os(macOS)
import Foundation
import LosttyRemote

/// Lostty Mobile: keeps one per-session tmux option (`@lostty_claude`,
/// `@lostty_skin`) matching what this Lostty's panes show. Only sessions
/// this process owns: several Lostty processes share the server and must
/// not fight. The one exception is clearing the option on sessions whose
/// Lostty is gone: no one else would ever clear it.
enum TmuxOptionSync {
    /// Runs `args` against the live sessions off the main thread.
    static func sync(
        option: String, desired: [String: String], current: @escaping @Sendable (RemoteSession) -> String?
    ) {
        let pid = ProcessInfo.processInfo.processIdentifier
        Task.detached(priority: .utility) {
            let client = TmuxClient()
            let changes = args(
                option: option, desired: desired, current: current, sessions: client.remoteSessions(), pid: pid)
            if !changes.isEmpty { client.run(changes) }
        }
    }

    /// One tmux call writing only what differs, then the signal; empty when
    /// tmux already agrees (so a wake never causes another wake). `desired`
    /// is keyed by pane (uuidString); a pane missing from it is unset.
    static func args(
        option: String, desired: [String: String], current: (RemoteSession) -> String?,
        sessions: [RemoteSession], pid: Int32, isAlive: (Int32) -> Bool = ProcessLiveness.isAlive
    ) -> [String] {
        var args: [String] = []
        for session in sessions {
            let want: String?
            if session.owner == pid {
                guard let pane = session.surface else { continue }
                want = desired[pane]
            } else if session.owner.map(isAlive) ?? false {
                continue  // another running Lostty's
            } else {
                want = nil
            }
            guard want != current(session) else { continue }
            if !args.isEmpty { args.append(";") }
            if let want {
                args += ["set-option", "-t", session.id, option, want]
            } else {
                args += ["set-option", "-u", "-t", session.id, option]
            }
        }
        if !args.isEmpty { args += [";"] + TmuxHooks.signalCommand }
        return args
    }
}
#endif
