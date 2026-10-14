#if os(macOS)
import Combine
import Foundation
import LosttyRemote

/// While Claude works in any pane, reads the panes every two seconds for
/// its working line, and stops the trace of one that lost it: an interrupt
/// (Esc, Ctrl+C) sends no hook, and Claude Code no longer animates the
/// title (`WorkingLineCheck`). The tmux listing already reads the line for
/// every session `ClaudeTmuxSync` marked working. Idle otherwise.
@MainActor
final class ClaudeWorkingLineWatch {
    static let shared = ClaudeWorkingLineWatch()

    private var check = WorkingLineCheck()
    private var watcher: AnyCancellable?
    private var timer: Timer?
    private var reading = false

    func start() {
        guard watcher == nil else { return }
        watcher = ClaudeRuntime.shared.$phases.sink { [weak self] phases in
            MainActor.assumeIsolated { self?.phasesChanged(phases) }
        }
    }

    private func phasesChanged(_ phases: [UUID: TracePhase]) {
        let racing = !Self.racing(phases).isEmpty
        if racing, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { ClaudeWorkingLineWatch.shared.tick() }
            }
        } else if !racing {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        guard !reading else { return }
        reading = true
        Task.detached(priority: .utility) {
            let sessions = TmuxClient().sessionListing()
            await MainActor.run { ClaudeWorkingLineWatch.shared.read(sessions) }
        }
    }

    private func read(_ sessions: [RemoteSession]) {
        reading = false
        let runtime = ClaudeRuntime.shared
        let racing = Self.racing(runtime.phases)
        var showing: [UUID: Bool] = [:]
        for session in sessions {
            // Only a session tmux has as working had its screen read.
            guard let id = session.surface.flatMap(UUID.init(uuidString:)), racing[id] != nil,
                  session.claude != nil else { continue }
            showing[id] = session.spinner != nil
        }
        for id in check.check(racing: racing, showing: showing, now: Date()) {
            runtime.workingLineGone(id)
        }
    }

    /// Panes whose trace runs for Claude itself (not only its subagents),
    /// and since when.
    private static func racing(_ phases: [UUID: TracePhase]) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for (id, phase) in phases {
            if case .racing(let since, subagents: false) = phase { result[id] = since }
        }
        return result
    }
}
#endif
