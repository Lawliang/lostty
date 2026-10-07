#if os(macOS)
import Foundation

/// The "agent isn't connected" notifications: every launch, one bubble per
/// installed agent (Claude, Codex) whose Lostty hooks are not set up, with a
/// Connect button that installs that agent's hooks.
enum HookNotifications {
    /// Installed agents whose hooks are missing or outdated. An unreadable
    /// settings file (or a status that could not be read) gets no bubble:
    /// Connect could not fix it; Lostty → Claude Integration… reports it.
    static func missingAgents(installed: [HookAgent], status: (HookAgent) -> ClaudeHooksStatus?) -> [HookAgent] {
        installed.filter { agent in
            switch status(agent) {
            case .notInstalled?, .partial?: true
            case .installed?, .unreadable?, nil: false
            }
        }
    }

    static func missing(_ agent: HookAgent, connect: (@MainActor () -> Void)? = nil) -> LosttyNotification {
        LosttyNotification(
            kind: .hooksMissing(agent),
            title: "\(agent.title) isn't connected",
            detail: "Lostty can't show the trace or Ready for response for \(agent.title).",
            actionTitle: "Connect",
            action: connect)
    }

    static func result(_ agent: HookAgent, exitCode: Int32, stderr: String) -> LosttyNotification {
        guard exitCode == 0 else {
            let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return LosttyNotification(
                kind: .hooks(agent), style: .failure,
                title: "Couldn't connect \(agent.title)",
                detail: reason.isEmpty ? "The Lostty command-line tool did not run." : reason)
        }
        var detail = "Restart any running \(agent.title) sessions to see the trace."
        if agent == .codex { detail += " Codex asks you to approve Lostty's hooks once." }
        return LosttyNotification(kind: .hooks(agent), style: .success, title: "\(agent.title) connected", detail: detail)
    }

    /// Run at launch: check each installed agent off the main thread, then
    /// post a bubble for each one that isn't connected.
    @MainActor
    static func checkAtLaunch(center: LosttyNotifications = .shared) {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let installed = HookAgent.allCases.filter {
            FileManager.default.fileExists(atPath: home.appendingPathComponent($0.configDirectory).path)
        }
        guard !installed.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let cli = ClaudeHooksCLI()
            let missing = missingAgents(installed: installed, status: { cli.status(agent: $0) })
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for agent in missing {
                        center.post(Self.missing(agent, connect: { connect(agent, center: center) }))
                    }
                }
            }
        }
    }

    @MainActor
    static func connect(_ agent: HookAgent, center: LosttyNotifications = .shared) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = ClaudeHooksCLI().run("install", agent: agent)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    center.post(result(agent, exitCode: outcome.exitCode, stderr: outcome.stderr))
                }
            }
        }
    }
}
#endif
