#if os(macOS)
import AppKit
import Foundation

/// Where each tmux session's active pane is, from `list-panes -a`.
enum PhonePanes {
    static let format = "#{session_id}\t#{pane_active}\t#{pane_current_path}"

    /// session id → its active pane's folder.
    static func activePaths(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3, f[0].hasPrefix("$"), !f[2].isEmpty else { continue }
            if f[1] == "1" || result[f[0]] == nil { result[f[0]] = f[2] }
        }
        return result
    }
}

/// The sessions the Branches panel places on branches.
enum SessionLocator {
    /// Every pane in every terminal window that has reported its folder.
    @MainActor
    static func panes() -> [BranchSession] {
        let claude = ClaudeRuntime.shared
        let usage = ClaudeUsageRuntime.shared
        return TerminalController.all.flatMap { controller in
            controller.surfaceTree.compactMap { view -> BranchSession? in
                guard let pwd = view.pwd, !pwd.isEmpty else { return nil }
                let title = view.title.isEmpty ? (pwd as NSString).lastPathComponent : view.title
                let agent = agentState(
                    phase: claude.phases[view.id] != nil,
                    awaiting: claude.awaiting.contains(view.id),
                    claudeOpen: usage.sessions.contains(view.id))
                return BranchSession(origin: .pane(view.id), title: title, pwd: pwd, agent: agent)
            }
        }
    }

    static func agentState(phase: Bool, awaiting: Bool, claudeOpen: Bool) -> AgentState? {
        if awaiting { return .waiting }
        if phase { return .working }
        if claudeOpen { return .idle }
        return nil
    }

    /// Tmux sessions no running Lostty shows (started on the phone), at
    /// their active pane's folder. Blocking.
    static func phoneSessions() -> [BranchSession] {
        let client = TmuxClient()
        let sessions = TmuxOwnership.available(client.sessions(), isAlive: ProcessLiveness.isAlive)
        guard !sessions.isEmpty, let output = client.run(["list-panes", "-a", "-F", PhonePanes.format]) else { return [] }
        let paths = PhonePanes.activePaths(output)
        return sessions.compactMap { session in
            paths[session.id].map {
                BranchSession(origin: .phone(sessionID: session.id), title: session.name, pwd: $0, agent: nil)
            }
        }
    }
}
#endif
