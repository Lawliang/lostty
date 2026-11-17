#if os(macOS)
import Combine
import Foundation
import LosttyRemote

/// While Claude works in any pane, reads the panes every two seconds for
/// its working line, and stops the trace of one that lost it: an interrupt
/// (Esc, Ctrl+C) sends no hook, and Claude Code no longer animates the
/// title (`WorkingLineCheck`). One tmux call reads every working pane's
/// screen. Idle otherwise.
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
        let ids = SessionSync.shared.sessionIDs
        let panes = Self.racing(ClaudeRuntime.shared.phases).keys.compactMap { pane in
            ids[pane].map { (pane: pane, session: $0) }
        }
        guard !panes.isEmpty else { return }
        reading = true
        Task.detached(priority: .utility) {
            let showing = TmuxClient().run(Self.args(panes)).map(Self.showing)
            await MainActor.run { ClaudeWorkingLineWatch.shared.read(showing) }
        }
    }

    /// `showing` is nil when tmux didn't answer (a session just ended):
    /// nothing is known, so nothing stops.
    private func read(_ showing: [UUID: Bool]?) {
        reading = false
        guard let showing else { return }
        let runtime = ClaudeRuntime.shared
        for id in check.check(racing: Self.racing(runtime.phases), showing: showing, now: Date()) {
            runtime.workingLineGone(id)
        }
    }

    /// Leads each pane's screen in the output of `args`.
    nonisolated static let marker = "@@lostty-pane "

    /// One tmux call printing each pane's screen under a line naming it.
    nonisolated static func args(_ panes: [(pane: UUID, session: String)]) -> [String] {
        var args: [String] = []
        for (pane, session) in panes {
            if !args.isEmpty { args.append(";") }
            args += ["display-message", "-p", "-t", session, marker + pane.uuidString, ";",
                     "capture-pane", "-pJ", "-t", session]
        }
        return args
    }

    /// Reads the output of `args`: whether each pane's last line that looks
    /// like Claude's working line ("✳ Incubating… (3m 51s)") is one.
    nonisolated static func showing(_ output: String) -> [UUID: Bool] {
        var result: [UUID: Bool] = [:]
        var pane: UUID?
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix(marker) {
                pane = UUID(uuidString: String(line.dropFirst(marker.count)))
                if let pane { result[pane] = false }
            } else if let pane, looksLikeWorkingLine(line) {
                result[pane] = ClaudeSpinner(line: String(line), seenAt: Date()) != nil
            }
        }
        return result
    }

    /// One of Claude's glyphs, a space, then an ellipsis somewhere after.
    private nonisolated static func looksLikeWorkingLine(_ line: Substring) -> Bool {
        let rest = line.drop { $0 == " " }
        return ClaudeSpinner.glyphs.contains { rest.hasPrefix($0 + " ") } && rest.contains("…")
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
