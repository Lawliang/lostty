#if os(macOS)
import AppKit
import Foundation
import LosttyRemote
import Security

/// Restart to Update: quit into the Lostty installed now without ending a
/// single session. This Lostty leaves a `RestartHandoff`, tags its sessions
/// as restarting (so nothing clears their state in the gap), forces window
/// restoration on, starts a helper that reopens the app once it has exited,
/// and terminates keeping its sessions (`isRestarting`). The new Lostty
/// restores every window, tab and split; each pane's launcher reattaches
/// to its session (`claimOrphan`), and `resumeIfRestarted` puts back the
/// rest.
@MainActor
enum LosttyRestart {
    enum Reason {
        case menu, script
        /// Sparkle relaunches the app itself once it has installed.
        case sparkle
    }

    /// While restarting, termination keeps the sessions and asks nothing.
    static var isRestarting = false

    static let keepWindowsKey = "NSQuitAlwaysKeepsWindows"

    /// The bundle this Lostty launched from: where the new build is
    /// installed, even after the old one was moved aside.
    static let bundlePath = Bundle.main.bundlePath

    /// Claims the restart; false when one is already underway.
    static func begin() -> Bool {
        guard !isRestarting else { return false }
        isRestarting = true
        return true
    }

    static func restart(reason: Reason) {
        guard begin() else { return }
        // Sparkle has put a whole, signed bundle there; anything else may be
        // a copy still in progress.
        if reason != .sparkle, !bundleIsComplete(atPath: bundlePath) {
            fail("The Lostty at \(bundlePath) isn't complete yet (still installing?). Try again in a moment.")
            return
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let stayAwake = StayAwakeStore.shared
        let hooks = ClaudeHooksCLI()
        let handoff = RestartHandoff(
            pid: pid, at: Date(),
            claude: Dictionary(uniqueKeysWithValues: ClaudeRuntime.shared.carry().map { ($0.key.uuidString, $0.value) }),
            stayAwakeOn: stayAwake.isOn, stayAwakeUntil: stayAwake.until,
            hookAgents: agentsWithHooks { hooks.status(agent: $0) },
            keepWindows: UserDefaults.ghostty.object(forKey: keepWindowsKey) as? Bool,
            transcripts: Dictionary(uniqueKeysWithValues: TurnObserver.shared.carry().map { ($0.key.uuidString, $0.value) }))
        do {
            try handoff.save(to: RestartHandoff.standardURL)
        } catch {
            fail("Lostty couldn't save what to restore (\(error.localizedDescription)).")
            return
        }
        if reason != .sparkle, !spawnDetached(reopenScript(pid: pid, bundle: bundlePath)) {
            try? FileManager.default.removeItem(at: RestartHandoff.standardURL)
            fail("Lostty couldn't start its relauncher.")
            return
        }
        // Its sessions aren't abandoned: no Lostty clears their state while
        // the next one starts.
        let tag = TmuxOptionSync.Restarting(pid: pid, until: Date().addingTimeInterval(TmuxOptionSync.Restarting.grace))
        TmuxClient().run(["set-option", "-g", TmuxOptionSync.Restarting.option, tag.tag])
        // Every window comes back, whatever "Close windows when quitting" says.
        UserDefaults.ghostty.set(true, forKey: keepWindowsKey)
        NSApp.invalidateRestorableState()
        for window in NSApp.windows { window.invalidateRestorableState() }
        if reason != .sparkle { NSApp.terminate(nil) }
    }

    /// At launch: if the last Lostty restarted (not crashed), put back what
    /// window restoration doesn't: the window setting, Claude's state, Stay
    /// Awake, and up-to-date hooks. Never in the test host. True when it did.
    @discardableResult
    static func resumeIfRestarted(
        from url: URL = RestartHandoff.standardURL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard environment["XCTestConfigurationFilePath"] == nil,
              let handoff = RestartHandoff.take(from: url),
              handoff.isFresh(now: Date(), isAlive: ProcessLiveness.isAlive) else { return false }
        if let keep = handoff.keepWindows {
            UserDefaults.ghostty.set(keep, forKey: keepWindowsKey)
        } else {
            UserDefaults.ghostty.removeObject(forKey: keepWindowsKey)
        }
        ClaudeRuntime.shared.restore(Dictionary(uniqueKeysWithValues: handoff.claude.compactMap { key, carry in
            UUID(uuidString: key).map { ($0, carry) }
        }))
        TurnObserver.shared.restore(Dictionary(uniqueKeysWithValues: (handoff.transcripts ?? [:]).compactMap { key, path in
            UUID(uuidString: key).map { ($0, path) }
        }))
        // Before StayAwakeStore.start(), which would otherwise restore the
        // power settings it left applied.
        if handoff.stayAwakeOn { StayAwakeStore.shared.resume(until: handoff.stayAwakeUntil) }
        let hooks = ClaudeHooksCLI()
        for agent in agentsToReinstall(had: handoff.hookAgents, status: { hooks.status(agent: $0) }) {
            _ = hooks.run("install", agent: agent)
        }
        return true
    }

    /// The agents with any of Lostty's hooks (current or not).
    nonisolated static func agentsWithHooks(status: (HookAgent) -> ClaudeHooksStatus?) -> [String] {
        HookAgent.allCases.filter { [.installed, .partial].contains(status($0)) }.map(\.rawValue)
    }

    /// Of the agents that had hooks, those the new build finds out of date.
    nonisolated static func agentsToReinstall(had: [String], status: (HookAgent) -> ClaudeHooksStatus?) -> [HookAgent] {
        had.compactMap(HookAgent.init(rawValue:)).filter { status($0) == .partial }
    }

    /// A whole, validly signed app at `path`: not one still being copied.
    nonisolated static func bundleIsComplete(atPath path: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
    }

    /// Waits for `pid` to exit, then opens `bundle` as a new instance.
    nonisolated static func reopenScript(pid: Int32, bundle: String) -> String {
        "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open -n \(TmuxRemote.shellQuote(bundle))"
    }

    /// Runs `script` with /bin/sh in its own session, outliving Lostty, with
    /// none of Lostty's file descriptors (stdio on /dev/null).
    nonisolated static func spawnDetached(_ script: String) -> Bool {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sh"), strdup("-c"), strdup(script), nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        return posix_spawn(&pid, "/bin/sh", &actions, &attributes, argv, environ) == 0
    }

    private static func fail(_ message: String) {
        isRestarting = false
        let alert = NSAlert()
        alert.messageText = "Couldn't restart Lostty"
        alert.informativeText = message + " Nothing was closed."
        alert.runModal()
    }
}
#endif
