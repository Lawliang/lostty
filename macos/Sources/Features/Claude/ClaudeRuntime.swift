#if os(macOS)
import Foundation
import Combine

/// App-wide Claude wiring: each pane's trace phase, fed by `+claude-state`
/// hooks (as the LOSTTY_CLAUDE user var) and by the pane's shell reporting
/// that a command finished.
@MainActor
final class ClaudeRuntime: ObservableObject {
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let shared = ClaudeRuntime()

    /// Only panes whose phase is not `.off`.
    @Published private(set) var phases: [UUID: TracePhase] = [:]

    /// Panes showing "Ready for response": Claude finished its turn (or asks
    /// for permission) while the pane was not focused, and nobody has
    /// looked at it since.
    @Published private(set) var awaiting: Set<UUID> = []

    /// What each pane's Claude (or one of its subagents) last set out to do,
    /// as `+claude-state tool` words a tool call: "Editing Foo.swift". Kept
    /// while it works and while it asks permission for that call; gone when
    /// it finishes its turn or exits, and on a new prompt.
    @Published private(set) var actions: [UUID: String] = [:]

    /// An agent finished its turn (or stopped to ask permission) in a pane,
    /// naming its conversation file: the turn observer's cue. Set at launch.
    var turnEnded: @MainActor (UUID, String) -> Void = { _, _ in }

    /// A pane's agent exited (SessionEnd, or the shell reported the command
    /// finished): the guard stops typing outcomes into it. Set at launch.
    var agentGone: @MainActor (UUID) -> Void = { _ in }

    /// A pane's agent sent a state message, naming which agent when it can
    /// tell: the guard learns the pane runs an agent, for its badge.
    var agentSeen: @MainActor (UUID, HookAgent?) -> Void = { _, _ in }

    /// What the context handoff hears: turn ends, prompts, a fresh window
    /// after /clear, and the pane's agent going away. Set at launch.
    var handoffSignal: @MainActor (UUID, ContextHandoffSignal) -> Void = { _, _ in }

    /// A pane's hook kept a SendMessage inside its zone, naming the agent
    /// it was for: the canvas's notice. Set at launch.
    var messageKeptInside: @MainActor (UUID, String) -> Void = { _, _ in }

    private let now: () -> Date
    private let schedule: Scheduler
    /// Panes not focused right now. Panes start focused (SurfaceView does).
    private var unfocused: Set<UUID> = []
    /// Panes whose current wait was already seen; reset when Claude works again.
    private var seen: Set<UUID> = []
    /// Panes whose title has shown a working spinner since the trace started.
    private var sawSpinner: Set<UUID> = []
    /// Panes whose hooks said a turn began (a prompt or a tool start) and no
    /// Stop has ended it: the handoff's turns. Not the trace: the title or
    /// working line stops that at a permission prompt, and Claude carries on
    /// after you approve with no new prompt.
    private var hookTurns: Set<UUID> = []

    init(
        now: @escaping () -> Date = Date.init,
        schedule: @escaping Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { work() }
            }
        }
    ) {
        self.now = now
        self.schedule = schedule
    }

    func phase(_ id: UUID) -> TracePhase { phases[id] ?? .off }

    func userVarChanged(_ id: UUID, name: String, value: String) {
        guard name == ClaudeConstants.userVarName else { return }
        if ClaudeMessage.isFresh(value) {
            handoffSignal(id, .fresh)
            return
        }
        if ClaudeMessage.isCleared(value) {
            handoffSignal(id, .cleared)
            return
        }
        if let target = ClaudeMessage.denied(value) { messageKeptInside(id, target) }
        if let action = ClaudeMessage.action(value) {
            // A tool starting means Claude works, even with no new prompt
            // (it carries on after a permission prompt without one).
            if phase(id).isOff { apply(.busy, to: id) }
            hookTurns.insert(id)
            setAction(action, for: id)
            agentSeen(id, ClaudeMessage.agentKind(value))
            return
        }
        guard let state = ClaudeMessage.decode(value) else {
            Ghostty.logger.debug("claude: rejected malformed \(ClaudeConstants.userVarName) payload")
            return
        }
        if state == .exit { agentGone(id) } else { agentSeen(id, ClaudeMessage.agentKind(value)) }
        // Only a turn that was under way ends: anything printed in a pane can
        // carry this user var, so an idle out of nowhere names no file.
        let turnUnderWay = !phase(id).isOff
        let permission = ClaudeMessage.isPermission(value)
        apply(state, to: id, permission: permission)
        switch state {
        case .busy:
            hookTurns.insert(id)
            handoffSignal(id, .prompted)
        case .exit: hookTurns.remove(id)
        default: break
        }
        if state == .exit { LastSessionStore.shared.agentGone(id) }
        guard state == .idle, let path = ClaudeMessage.transcript(value) else { return }
        // The conversation to resume after the Mac restarts.
        LastSessionStore.shared.conversation(id, transcript: path)
        if turnUnderWay { turnEnded(id, path) }
        if !permission, hookTurns.remove(id) != nil { handoffSignal(id, .stopped(transcript: path)) }
    }

    /// The pane's shell reported a command finished, so whatever ran there
    /// (claude included) is gone: a racing trace must not stay up.
    func commandFinished(_ id: UUID) {
        agentGone(id)
        LastSessionStore.shared.agentGone(id)
        apply(.exit, to: id)
        hookTurns.remove(id)
        handoffSignal(id, .gone)
    }

    func surfaceClosed(_ id: UUID) {
        agentGone(id)
        LastSessionStore.shared.agentGone(id)
        phases[id] = nil
        unfocused.remove(id)
        seen.remove(id)
        awaiting.remove(id)
        sawSpinner.remove(id)
        hookTurns.remove(id)
        setAction(nil, for: id)
        handoffSignal(id, .gone)
    }

    /// A pane is focused when its window is key and it is the selected pane.
    /// Focusing a waiting pane counts as seeing it.
    func focusChanged(_ id: UUID, focused: Bool) {
        if focused {
            unfocused.remove(id)
            seen.insert(id)
            awaiting.remove(id)
        } else {
            unfocused.insert(id)
        }
    }

    /// Lostty Mobile: a phone attached to this pane's session. Seeing it
    /// there counts like focusing it here.
    func seenElsewhere(_ id: UUID) {
        guard awaiting.contains(id) else { return }
        seen.insert(id)
        awaiting.remove(id)
    }

    /// Agents titled the pane with a spinner while working: Claude "◐ …"
    /// (then "✳ …" when idle), Codex "⠋ …" (then just the folder name).
    /// An Esc interrupt sends no Stop hook, so a racing pane whose title
    /// turns idle stops at once. A title without a spinner only counts as
    /// idle after a spinner was seen: Claude Code 2.1 keeps "✳ …" while it
    /// works too, so "✳" alone would stop the trace every time Claude
    /// retitles the pane mid-turn (its interrupts are caught by
    /// `workingLineGone` instead). Only title changes count: a title left
    /// over from before the prompt never stops the trace that prompt started.
    /// While only subagents work, Claude's own title is idle; that is no
    /// interrupt, and a spinner then means Claude took over again.
    func titleChanged(_ id: UUID, title: String) {
        let subagents = isSubagentsOnly(id)
        if Self.isSpinner(title) {
            sawSpinner.insert(id)
            // Working again (e.g. after a permission prompt, which sends no
            // UserPromptSubmit): the next wait is new.
            seen.remove(id)
            if subagents { apply(.resumed, to: id) }
            return
        }
        guard !subagents, sawSpinner.contains(id) else { return }
        if case .racing = phase(id) { apply(.exit, to: id) }
    }

    /// Claude's working line left a racing pane's screen and stayed gone
    /// (`WorkingLineCheck`): it was interrupted, and waits for you.
    func workingLineGone(_ id: UUID) {
        guard case .racing(_, subagents: false) = phase(id) else { return }
        apply(.idle, to: id)
    }

    private func isSubagentsOnly(_ id: UUID) -> Bool {
        if case .racing(_, subagents: true) = phase(id) { return true }
        return false
    }

    /// `permission`: an `idle` that asks permission for the last action,
    /// which then stays to say what it asks.
    func apply(_ state: ClaudeState, to id: UUID, permission: Bool = false) {
        let next = phase(id).applying(state, now: now())
        store(next, for: id)

        if next == .off { sawSpinner.remove(id) }
        switch state {
        case .busy, .agents:
            // Subagents still working means Claude carries on by itself:
            // nothing to respond to yet.
            seen.remove(id)
            awaiting.remove(id)
            // A new prompt: the last one's action is done.
            if state == .busy { setAction(nil, for: id) }
        case .resumed:
            break
        case .exit:
            awaiting.remove(id)
            setAction(nil, for: id)
        case .idle:
            if !permission { setAction(nil, for: id) }
            // Waiting for the user. Focused now means they see it already.
            if !unfocused.contains(id) {
                seen.insert(id)
            } else if !seen.contains(id) {
                awaiting.insert(id)
            }
        }
    }

    /// Working-title spinners: Claude's ◐◑◒◓, Codex's braille dots.
    static func isSpinner(_ title: String) -> Bool {
        guard let first = title.unicodeScalars.first else { return false }
        return "◐◑◒◓".unicodeScalars.contains(first) || (0x2801...0x28FF).contains(first.value)
    }

    /// Debug builds: a fake busy (4s) → subagents only (6s) → idle cycle to
    /// review a style and the bottom-edge hand-off by eye.
    func debugCycle(_ id: UUID) {
        apply(.busy, to: id)
        schedule(4) { [weak self] in self?.apply(.agents, to: id) }
        schedule(10) { [weak self] in self?.apply(.idle, to: id) }
    }

    private func setAction(_ action: String?, for id: UUID) {
        if actions[id] != action { actions[id] = action }
    }

    private func store(_ phase: TracePhase, for id: UUID) {
        let value: TracePhase? = phase.isOff ? nil : phase
        if phases[id] != value { phases[id] = value }
    }
}

/// A pane's Claude as a restart hands it on (`LosttyRestart`): hooks fired
/// while Lostty is down are lost, so the new Lostty starts from this.
struct ClaudeCarry: Codable, Equatable {
    enum Activity: String, Codable {
        case working, subagents, waiting
    }

    var activity: Activity
    var action: String?
}

extension ClaudeRuntime {
    /// What each pane's Claude is doing now, for a restart to hand on.
    func carry() -> [UUID: ClaudeCarry] {
        var carried: [UUID: ClaudeCarry] = [:]
        for (id, phase) in phases {
            guard case .racing(_, let subagents) = phase else { continue }
            carried[id] = ClaudeCarry(activity: subagents ? .subagents : .working, action: actions[id])
        }
        for id in awaiting {
            carried[id] = ClaudeCarry(activity: .waiting, action: actions[id])
        }
        return carried
    }

    /// After a restart: the panes' Claudes as the old Lostty last saw them.
    /// The restored panes keep their UUIDs.
    func restore(_ carried: [UUID: ClaudeCarry]) {
        for (id, carry) in carried {
            switch carry.activity {
            case .working: store(.racing(since: now()), for: id)
            case .subagents: store(.racing(since: now(), subagents: true), for: id)
            case .waiting: awaiting.insert(id)
            }
            setAction(carry.action, for: id)
        }
    }
}

/// One pane's share of `ClaudeRuntime`, for the views over that pane: they
/// update when its Claude changes, not each time any pane's does (a tool
/// call anywhere changes `actions`, and every pane has these views).
@MainActor
final class PaneClaude: ObservableObject {
    @Published private(set) var phase: TracePhase = .off
    @Published private(set) var awaiting = false
    private var watchers: Set<AnyCancellable> = []

    init(_ id: UUID, runtime: ClaudeRuntime = .shared) {
        runtime.$phases.map { $0[id] ?? .off }.removeDuplicates()
            .sink { [weak self] in self?.phase = $0 }
            .store(in: &watchers)
        runtime.$awaiting.map { $0.contains(id) }.removeDuplicates()
            .sink { [weak self] in self?.awaiting = $0 }
            .store(in: &watchers)
    }
}
#endif
