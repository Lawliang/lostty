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
            let restarting = client.run(["show-option", "-gqv", Restarting.option]).flatMap(Restarting.init(tag:))
            let changes = args(
                option: option, desired: desired, current: current, sessions: client.remoteSessions(), pid: pid,
                restarting: restarting)
            if !changes.isEmpty { client.run(changes) }
        }
    }

    /// One tmux call writing only what differs, then the signal; empty when
    /// tmux already agrees (so a wake never causes another wake). `desired`
    /// is keyed by pane (uuidString); a pane missing from it is unset.
    static func args(
        option: String, desired: [String: String], current: (RemoteSession) -> String?,
        sessions: [RemoteSession], pid: Int32, isAlive: (Int32) -> Bool = ProcessLiveness.isAlive,
        restarting: Restarting? = nil, now: Date = Date()
    ) -> [String] {
        var args: [String] = []
        for session in sessions {
            let want: String?
            if session.owner == pid {
                guard let pane = session.surface else { continue }
                want = desired[pane]
            } else if session.owner.map(isAlive) ?? false {
                continue  // another running Lostty's
            } else if let restarting, session.owner == restarting.pid, now < restarting.until {
                continue  // its Lostty is restarting: the next one takes it over
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

    /// Restart to Update (`LosttyRestart`): the restarting Lostty's pid and
    /// when its tag lapses, as the server-wide `@lostty_restarting` holds
    /// them ("77 2000000030"). Until then its sessions aren't abandoned.
    struct Restarting: Equatable, Sendable {
        static let option = "@lostty_restarting"
        /// Long enough for the new Lostty's panes to reattach.
        static let grace: TimeInterval = 30

        var pid: Int32
        var until: Date

        init(pid: Int32, until: Date) {
            self.pid = pid
            self.until = until
        }

        init?(tag: String) {
            let parts = tag.split(separator: " ")
            guard parts.count == 2, let pid = Int32(parts[0]), let seconds = TimeInterval(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            else { return nil }
            self.init(pid: pid, until: Date(timeIntervalSince1970: seconds))
        }

        var tag: String { "\(pid) \(Int(until.timeIntervalSince1970))" }
    }
}
#endif
