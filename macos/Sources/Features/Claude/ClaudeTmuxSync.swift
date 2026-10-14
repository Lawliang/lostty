#if os(macOS)
import Combine
import Foundation
import LosttyRemote

/// Lostty Mobile: writes each of this Lostty's sessions' Claude state into
/// tmux (`@lostty_claude`: waiting, working, or unset) whenever
/// `ClaudeRuntime` changes, then wakes watchers, so the phone shows
/// "Waiting" and "Working"; and, while it works or waits, what it's doing
/// (`@lostty_action`); and its context window (`@lostty_context`), for the
/// phone's top bar. Only sessions this process owns: several Lostty
/// processes share the server and must not fight. The one exception is
/// clearing the state of sessions whose Lostty is gone.
@MainActor
final class ClaudeTmuxSync {
    static let shared = ClaudeTmuxSync()

    private var watchers: Set<AnyCancellable> = []

    func start() {
        guard watchers.isEmpty else { return }
        let runtime = ClaudeRuntime.shared
        runtime.$phases.combineLatest(runtime.$awaiting, runtime.$actions)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { phases, awaiting, actions in
                Self.sync(phases: phases, awaiting: awaiting, actions: actions)
            }
            .store(in: &watchers)
        // Claude reports its context after each reply.
        ClaudeUsageRuntime.shared.$contexts
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { Self.syncContexts($0) }
            .store(in: &watchers)
        // A session made after the change, or a write tmux dropped, catches up.
        NotificationCenter.default.publisher(for: .losttySessionsChanged)
            .sink { _ in
                MainActor.assumeIsolated {
                    let runtime = ClaudeRuntime.shared
                    Self.sync(phases: runtime.phases, awaiting: runtime.awaiting, actions: runtime.actions)
                    Self.syncContexts(ClaudeUsageRuntime.shared.contexts)
                }
            }
            .store(in: &watchers)
    }

    nonisolated private static func syncContexts(_ contexts: [UUID: ClaudeUsageReport.Context]) {
        TmuxOptionSync.sync(
            option: TmuxRemote.contextOption,
            desired: Dictionary(uniqueKeysWithValues: contexts.map { id, context in
                (id.uuidString, SessionContext(used: context.used, size: context.size).encoded)
            }),
            current: { $0.context?.encoded })
    }

    nonisolated private static func sync(phases: [UUID: TracePhase], awaiting: Set<UUID>, actions: [UUID: String]) {
        let desired = desired(phases: Set(phases.keys), awaiting: awaiting, subagents: subagents(phases))
        TmuxOptionSync.sync(
            option: TmuxRemote.claudeOption, desired: desired.mapValues(\.rawValue), current: { $0.claude?.rawValue })
        TmuxOptionSync.sync(
            option: TmuxRemote.actionOption,
            desired: desiredActions(actions, showing: Set(desired.keys)), current: { $0.action })
    }

    /// Pane (uuidString) → its action, for the panes `showing` a state
    /// (working or waiting); cleaned to one line for the listing.
    nonisolated static func desiredActions(_ actions: [UUID: String], showing: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        for (id, action) in actions where showing.contains(id.uuidString) {
            result[id.uuidString] = SessionLabel.cleanLabel(action)
        }
        return result
    }

    /// Pane (uuidString) → what tmux should hold. A pane missing is unset.
    /// Only subagents working says so, for the phone's trace.
    nonisolated static func desired(
        phases: Set<UUID>, awaiting: Set<UUID>, subagents: Set<UUID> = []
    ) -> [String: ClaudeActivity] {
        var result: [String: ClaudeActivity] = [:]
        for id in phases { result[id.uuidString] = subagents.contains(id) ? .subagents : .working }
        for id in awaiting { result[id.uuidString] = .waiting }
        return result
    }

    /// Panes where only subagents work.
    nonisolated static func subagents(_ phases: [UUID: TracePhase]) -> Set<UUID> {
        Set(phases.compactMap { id, phase in
            if case .racing(_, subagents: true) = phase { return id }
            return nil
        })
    }

    /// See `TmuxOptionSync.args`.
    nonisolated static func args(
        desired: [String: ClaudeActivity], sessions: [RemoteSession], pid: Int32,
        isAlive: (Int32) -> Bool = ProcessLiveness.isAlive
    ) -> [String] {
        TmuxOptionSync.args(
            option: TmuxRemote.claudeOption, desired: desired.mapValues(\.rawValue), current: { $0.claude?.rawValue },
            sessions: sessions, pid: pid, isAlive: isAlive)
    }
}
#endif
