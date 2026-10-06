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

    /// How long a racing pane's title must read idle before the trace ends.
    static let idleTitleGrace: TimeInterval = 2.5

    private let now: () -> Date
    private let schedule: Scheduler
    /// When each pane's title last switched to Claude's idle marker.
    private var idleTitleSince: [UUID: Date] = [:]

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
        idleTitleSince[id] = nil
    }

    /// Claude Code titles the pane "✳ …" when idle and with a spinner while
    /// working. An Esc interrupt sends no Stop hook, so a racing pane whose
    /// title stays idle for `idleTitleGrace` stops.
    func titleChanged(_ id: UUID, title: String) {
        guard title.hasPrefix("✳") else {
            idleTitleSince[id] = nil
            return
        }
        if idleTitleSince[id] == nil { idleTitleSince[id] = now() }
        checkIdleTitle(id)
    }

    func apply(_ state: ClaudeState, to id: UUID) {
        let next = phase(id).applying(state, now: now())
        store(next, for: id)
        if case .racing = next, state == .busy { checkIdleTitle(id) }
    }

    /// Debug builds: a fake 4s busy → idle cycle to review a style by eye.
    func debugCycle(_ id: UUID) {
        apply(.busy, to: id)
        schedule(4) { [weak self] in self?.apply(.idle, to: id) }
    }

    private func checkIdleTitle(_ id: UUID) {
        schedule(Self.idleTitleGrace) { [weak self] in
            guard let self, case .racing = self.phase(id), let since = self.idleTitleSince[id],
                  self.now().timeIntervalSince(since) >= Self.idleTitleGrace else { return }
            self.apply(.exit, to: id)
        }
    }

    private func store(_ phase: TracePhase, for id: UUID) {
        let value: TracePhase? = phase.isOff ? nil : phase
        if phases[id] != value { phases[id] = value }
    }
}
#endif
