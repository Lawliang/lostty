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
            detail: agent == .claude
                ? "Lostty's guard and trace aren't set up for Claude: critical actions aren't checked, "
                    + "and there's no trace, Ready for response or usage."
                : "Lostty's guard and trace aren't set up for \(agent.title): critical actions aren't checked, "
                    + "and there's no trace or Ready for response.",
            actionTitle: "Connect",
            action: connect)
    }

    static let codexTrustMessage = "Open Codex once and approve Lostty's hooks so the guard can run."

    /// `codexTrusted`: for Codex, whether its config.toml already trusts a
    /// Lostty guard hook (nil when unknown or not Codex).
    static func result(_ agent: HookAgent, exitCode: Int32, stderr: String, codexTrusted: Bool? = nil) -> LosttyNotification {
        guard exitCode == 0 else {
            let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return LosttyNotification(
                kind: .hooks(agent), style: .failure,
                title: "Couldn't connect \(agent.title)",
                detail: reason.isEmpty ? "The Lostty command-line tool did not run." : reason)
        }
        var detail = "Lostty's guard and trace are set up for \(agent.title). "
            + "Restart any running \(agent.title) sessions: they pick up the hooks only when they start."
        if agent == .codex, codexTrusted != true { detail += " " + codexTrustMessage }
        return LosttyNotification(kind: .hooks(agent), style: .success, title: "\(agent.title) connected", detail: detail)
    }

    /// Whether Codex's config.toml has trusted a PreToolUse hook from the
    /// user's own `<home>/.codex/hooks.json`: a
    /// `[hooks.state."…/.codex/hooks.json:pre_tool_use:…"]` table (or an
    /// inline entry) with a `trusted_hash`. A project's hooks.json doesn't
    /// count. Best effort, presence only; the hash itself isn't checked.
    static func codexTrustsGuard(configToml: String, home: String) -> Bool {
        let key = "\(home)/.codex/hooks.json:pre_tool_use:"
        var inGuardTable = false
        for raw in configToml.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inGuardTable = line.hasPrefix("[hooks.state.") && line.contains("\"\(key)")
                continue
            }
            if line.contains("\"\(key)") && line.contains("trusted_hash") { return true }
            if inGuardTable && line.hasPrefix("trusted_hash") { return true }
        }
        return false
    }

    /// Reads ~/.codex/config.toml; false when it can't be read.
    static func codexTrustsGuard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let url = home.appendingPathComponent(".codex/config.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return codexTrustsGuard(configToml: text, home: home.path)
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

    /// Posts the "hooks missing" bubble for one agent, as checkAtLaunch does.
    @MainActor
    static func announceMissing(_ agent: HookAgent, center: LosttyNotifications = .shared) {
        center.post(missing(agent, connect: { connect(agent, center: center) }))
    }

    @MainActor
    static func connect(_ agent: HookAgent, center: LosttyNotifications = .shared) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = ClaudeHooksCLI().run("install", agent: agent)
            let trusted: Bool? = agent == .codex && outcome.exitCode == 0 ? codexTrustsGuard() : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    center.post(result(agent, exitCode: outcome.exitCode, stderr: outcome.stderr, codexTrusted: trusted))
                }
            }
        }
    }
}
#endif
