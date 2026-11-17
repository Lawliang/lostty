#if os(macOS)
import Foundation
import LosttyRemote

/// Lostty Mobile: keeps one per-session tmux option (`@lostty_claude`,
/// `@lostty_skin`) matching what this Lostty's panes show. Only sessions
/// this process owns: several Lostty processes share the server and must
/// not fight. The one exception is clearing the option on sessions whose
/// Lostty is gone: no one else would ever clear it.
///
/// Every option synced at about the same time shares one `list-sessions`
/// and one write: each tmux call is a process, and a tmux change syncs
/// them all.
enum TmuxOptionSync {
    /// One option's latest wish: what each pane should hold, and how to
    /// read what a session holds now.
    struct Wish {
        var desired: [String: String]
        var current: @Sendable (RemoteSession) -> String?
    }

    /// How long a sync waits for the other options' syncs, so a tmux change
    /// (which syncs every option) lists the sessions once, not once each.
    static let gather: TimeInterval = 0.05

    private static let queue = DispatchQueue(label: "Lostty tmux options", qos: .utility)
    /// Wishes not yet written; only touched on `queue`.
    nonisolated(unsafe) private static var waiting: [String: Wish] = [:]

    /// Writes `option` to the live sessions off the main thread, together
    /// with every other option synced within `gather`.
    static func sync(
        option: String, desired: [String: String], current: @escaping @Sendable (RemoteSession) -> String?
    ) {
        queue.async {
            let first = waiting.isEmpty
            waiting[option] = Wish(desired: desired, current: current)
            if first { queue.asyncAfter(deadline: .now() + gather) { flush() } }
        }
    }

    private static func flush() {
        let wishes = waiting
        waiting = [:]
        let pid = ProcessInfo.processInfo.processIdentifier
        let client = TmuxClient()
        let sessions = client.remoteSessions()
        // Only a session whose Lostty is gone asks whether it is restarting.
        let restarting = sessions.contains(where: { isAbandoned($0, pid: pid) })
            ? client.run(["show-option", "-gqv", Restarting.option]).flatMap(Restarting.init(tag:)) : nil
        let changes = args(wishes, sessions: sessions, pid: pid, restarting: restarting)
        if !changes.isEmpty { client.run(changes) }
    }

    /// One tmux call writing what differs for every option in `wishes`,
    /// then one signal; empty when tmux already agrees.
    static func args(
        _ wishes: [String: Wish], sessions: [RemoteSession], pid: Int32,
        isAlive: (Int32) -> Bool = ProcessLiveness.isAlive, restarting: Restarting? = nil, now: Date = Date()
    ) -> [String] {
        var args: [String] = []
        for (option, wish) in wishes.sorted(by: { $0.key < $1.key }) {
            let next = changes(
                option: option, desired: wish.desired, current: wish.current, sessions: sessions, pid: pid,
                isAlive: isAlive, restarting: restarting, now: now)
            if !args.isEmpty, !next.isEmpty { args.append(";") }
            args += next
        }
        return args.isEmpty ? [] : args + [";"] + TmuxHooks.signalCommand
    }

    private static func isAbandoned(
        _ session: RemoteSession, pid: Int32, isAlive: (Int32) -> Bool = ProcessLiveness.isAlive
    ) -> Bool {
        session.owner != pid && !(session.owner.map(isAlive) ?? false)
    }

    /// One tmux call writing only what differs, then the signal; empty when
    /// tmux already agrees (so a wake never causes another wake). `desired`
    /// is keyed by pane (uuidString); a pane missing from it is unset.
    static func args(
        option: String, desired: [String: String], current: (RemoteSession) -> String?,
        sessions: [RemoteSession], pid: Int32, isAlive: (Int32) -> Bool = ProcessLiveness.isAlive,
        restarting: Restarting? = nil, now: Date = Date()
    ) -> [String] {
        let args = changes(
            option: option, desired: desired, current: current, sessions: sessions, pid: pid, isAlive: isAlive,
            restarting: restarting, now: now)
        return args.isEmpty ? [] : args + [";"] + TmuxHooks.signalCommand
    }

    /// `args` without the signal, to chain several options into one call.
    static func changes(
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
            } else if !isAbandoned(session, pid: pid, isAlive: isAlive) {
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
