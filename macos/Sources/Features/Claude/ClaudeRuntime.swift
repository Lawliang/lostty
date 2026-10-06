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

    private let now: () -> Date
    private let schedule: Scheduler
    /// Panes not focused right now. Panes start focused (SurfaceView does).
    private var unfocused: Set<UUID> = []
    /// Panes whose current wait was already seen; reset when Claude works again.
    private var seen: Set<UUID> = []
    /// Panes whose title has shown a working spinner since the trace started.
    private var sawSpinner: Set<UUID> = []

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
        guard let state = ClaudeMessage.decode(value) else {
            Ghostty.logger.debug("claude: rejected malformed \(ClaudeConstants.userVarName) payload")
            return
        }
        apply(state, to: id)
    }

    /// The pane's shell reported a command finished, so whatever ran there
    /// (claude included) is gone: a racing trace must not stay up.
    func commandFinished(_ id: UUID) {
        apply(.exit, to: id)
    }

    func surfaceClosed(_ id: UUID) {
        phases[id] = nil
        unfocused.remove(id)
        seen.remove(id)
        awaiting.remove(id)
        sawSpinner.remove(id)
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

    /// Agents title the pane with a spinner while working: Claude "◐ …"
    /// (then "✳ …" when idle), Codex "⠋ …" (then just the folder name).
    /// An Esc interrupt sends no Stop hook, so a racing pane whose title
    /// turns idle stops at once. A title without a spinner only counts as
    /// idle after a spinner was seen, so panes whose titles never show one
    /// (e.g. inside tmux) keep their trace until a hook ends it. Only title
    /// changes count: a title left over from before the prompt never stops
    /// the trace that prompt started.
    func titleChanged(_ id: UUID, title: String) {
        if Self.isSpinner(title) {
            sawSpinner.insert(id)
            // Working again (e.g. after a permission prompt, which sends no
            // UserPromptSubmit): the next wait is new.
            seen.remove(id)
            return
        }
        guard title.hasPrefix("✳") || sawSpinner.contains(id) else { return }
        if case .racing = phase(id) { apply(.exit, to: id) }
    }

    func apply(_ state: ClaudeState, to id: UUID) {
        let next = phase(id).applying(state, now: now())
        store(next, for: id)

        if next == .off { sawSpinner.remove(id) }
        switch state {
        case .busy:
            seen.remove(id)
            awaiting.remove(id)
        case .exit:
            awaiting.remove(id)
        case .idle:
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

    /// Debug builds: a fake 4s busy → idle cycle to review a style by eye.
    func debugCycle(_ id: UUID) {
        apply(.busy, to: id)
        schedule(4) { [weak self] in self?.apply(.idle, to: id) }
    }

    private func store(_ phase: TracePhase, for id: UUID) {
        let value: TracePhase? = phase.isOff ? nil : phase
        if phases[id] != value { phases[id] = value }
    }
}
#endif
