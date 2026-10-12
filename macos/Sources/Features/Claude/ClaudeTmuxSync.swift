#if os(macOS)
import Combine
import Foundation
import LosttyRemote

/// Lostty Mobile: writes each of this Lostty's sessions' Claude state into
/// tmux (`@lostty_claude`: waiting, working, or unset) whenever
/// `ClaudeRuntime` changes, then wakes watchers, so the phone shows
/// "Waiting" and "Working". Only sessions this process owns: several Lostty
/// processes share the server and must not fight. The one exception is
/// clearing the state of sessions whose Lostty is gone.
@MainActor
final class ClaudeTmuxSync {
    static let shared = ClaudeTmuxSync()

    private var watchers: Set<AnyCancellable> = []

    func start() {
        guard watchers.isEmpty else { return }
        let runtime = ClaudeRuntime.shared
        runtime.$phases.combineLatest(runtime.$awaiting)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { phases, awaiting in
                Self.sync(Self.desired(phases: Set(phases.keys), awaiting: awaiting))
            }
            .store(in: &watchers)
        // A session made after the change, or a write tmux dropped, catches up.
        NotificationCenter.default.publisher(for: .losttySessionsChanged)
            .sink { _ in
                MainActor.assumeIsolated {
                    let runtime = ClaudeRuntime.shared
                    Self.sync(Self.desired(phases: Set(runtime.phases.keys), awaiting: runtime.awaiting))
                }
            }
            .store(in: &watchers)
    }

    nonisolated private static func sync(_ desired: [String: ClaudeActivity]) {
        let pid = ProcessInfo.processInfo.processIdentifier
        Task.detached(priority: .utility) {
            let client = TmuxClient()
            let changes = Self.args(desired: desired, sessions: client.remoteSessions(), pid: pid)
            if !changes.isEmpty { client.run(changes) }
        }
    }

    /// Pane (uuidString) → what tmux should hold. A pane missing is unset.
    nonisolated static func desired(phases: Set<UUID>, awaiting: Set<UUID>) -> [String: ClaudeActivity] {
        var result: [String: ClaudeActivity] = [:]
        for id in phases { result[id.uuidString] = .working }
        for id in awaiting { result[id.uuidString] = .waiting }
        return result
    }

    /// One tmux call writing only what differs, then the signal; empty when
    /// tmux already agrees (so a wake never causes another wake). A session
    /// whose Lostty is gone (crashed, or let go) keeps no Claude state: no
    /// one would ever clear a stale "Waiting" on the phone.
    nonisolated static func args(
        desired: [String: ClaudeActivity], sessions: [RemoteSession], pid: Int32,
        isAlive: (Int32) -> Bool = ProcessLiveness.isAlive
    ) -> [String] {
        var args: [String] = []
        for session in sessions {
            let want: ClaudeActivity?
            if session.owner == pid {
                guard let pane = session.surface else { continue }
                want = desired[pane]
            } else if session.owner.map(isAlive) ?? false {
                continue  // another running Lostty's
            } else {
                want = nil
            }
            guard want != session.claude else { continue }
            if !args.isEmpty { args.append(";") }
            if let want {
                args += ["set-option", "-t", session.id, TmuxRemote.claudeOption, want.rawValue]
            } else {
                args += ["set-option", "-u", "-t", session.id, TmuxRemote.claudeOption]
            }
        }
        if !args.isEmpty { args += [";"] + TmuxHooks.signalCommand }
        return args
    }
}
#endif
