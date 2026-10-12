#if os(macOS)
import Foundation
import LosttyRemote

/// Runs `tmux -L lostty …` synchronously. Each call takes a few
/// milliseconds; run it off the main thread except where a decision is
/// needed right away (close confirmation, quitting).
struct TmuxClient {
    /// Homebrew's places first: Lostty started from the Dock has a bare PATH.
    static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]

    var tmuxPath: String? = TmuxClient.locate()

    /// How long a call may take before Lostty gives up on it: a hung tmux
    /// must not freeze closing a pane or quitting.
    var timeout: TimeInterval = 2

    static func locate(
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let fromPath = (path ?? "").split(separator: ":").map { "\($0)/tmux" }
        return (candidates + fromPath).first(where: isExecutable)
    }

    /// stdout of `tmux -L lostty <args>` when it exits 0; nil when tmux is
    /// missing, no server is running, the command fails, or it takes longer
    /// than `timeout` (then it is killed).
    ///
    /// Waits on semaphores, not `waitUntilExit`, which spins the run loop:
    /// on the main thread that let other events run in the middle of
    /// closing a pane or quitting.
    @discardableResult
    func run(_ args: [String]) -> String? {
        guard let tmuxPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        // -u: the app may run without a UTF-8 locale; without it tmux turns
        // the tab separators in -F output into `_`.
        process.arguments = ["-u", "-L", TmuxConstants.socket] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }

        // Read while it runs, so a full pipe can't stall it. A private queue,
        // not the global one: callers may be blocking every cooperative
        // thread, and then global-queue work never gets a thread
        // (see ProcessRunner).
        let output = Output()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue(label: "lostty.tmux.read", qos: .userInitiated).async {
            output.data = out.fileHandleForReading.readDataToEndOfFile()
            read.signal()
        }

        let deadline = DispatchTime.now() + timeout
        guard exited.wait(timeout: deadline) == .success else {
            kill(process.processIdentifier, SIGKILL)
            return nil
        }
        guard read.wait(timeout: deadline) == .success,
              process.terminationStatus == 0 else { return nil }
        return String(decoding: output.data, as: UTF8.self)
    }

    /// Hands stdout from the reading queue back to `run`; the semaphore
    /// orders the write before the read.
    private final class Output: @unchecked Sendable {
        var data = Data()
    }

    func sessions() -> [TmuxSession] {
        run(["list-sessions", "-F", TmuxSession.listFormat]).map(TmuxSession.parseList) ?? []
    }

    /// Every session with the phone's columns (label, Claude state, title,
    /// folder, last use), for the menu bar and the sync.
    func remoteSessions() -> [RemoteSession] {
        run(["list-sessions", "-F", TmuxRemote.listFormat]).map(TmuxRemote.parse) ?? []
    }

    /// Wakes everything waiting on `lostty-changed`: the phone's list, other
    /// Lostty processes, this one's watcher.
    func signalChanged() {
        run(TmuxHooks.signalArgs)
    }

    /// Ends `session`, first noting why (`@lostty_end_<n>`), so a phone
    /// attached to it can say so.
    func end(_ session: TmuxSession, reason: String) {
        run(Self.endArgs(session, reason: reason))
    }

    static func endArgs(_ session: TmuxSession, reason: String) -> [String] {
        guard let option = try? TmuxRemote.endOption(sessionID: session.id) else {
            return ["kill-session", "-t", session.id]
        }
        return ["set-option", "-g", option, reason, ";", "kill-session", "-t", session.id]
    }

    /// Ends the session showing pane `surface`: closing a pane ends its
    /// shell, as on a plain terminal.
    func endSessions(showing surface: UUID, ownedBy pid: Int32) {
        for session in TmuxOwnership.showing(surface, ownedBy: pid, in: sessions()) {
            end(session, reason: TmuxRemote.EndTag.macClose)
        }
    }

    /// Ends every session Lostty `pid` shows: quitting ends its shells.
    func endSessions(ownedBy pid: Int32) {
        for session in TmuxOwnership.owned(by: pid, in: sessions()) {
            end(session, reason: TmuxRemote.EndTag.macQuit)
        }
    }

    /// Lets go of a session: no Lostty shows it any more, so it is not
    /// offered after a crash again; it stays running for the phone and
    /// for Open Session. Its Claude state goes too (no Lostty keeps it
    /// current), and the phone's list hears of it.
    func disown(_ session: TmuxSession) {
        run(["set-option", "-u", "-t", session.id, TmuxConstants.surfaceOption, ";",
             "set-option", "-u", "-t", session.id, TmuxConstants.ownerOption, ";",
             "set-option", "-u", "-t", session.id, TmuxRemote.claudeOption, ";"]
            + TmuxHooks.signalCommand)
    }

    /// The server outlives its last session (`exit-empty off`), so a phone
    /// can still read why a session ended. At launch one left empty is
    /// stopped, so the next session starts a server with the current
    /// tmux.conf and environment, and the old end reasons go with it.
    /// Runs synchronously in `applicationWillFinishLaunching`, before any
    /// window exists, so this Lostty's own sessions cannot be caught by the
    /// kill. tmux decides in one command, so the check and the kill cannot
    /// be split by a session made between them; another Lostty or the phone
    /// creating a session at that exact instant is still a theoretical race.
    /// `-f /dev/null`: never starts a server.
    static let stopIfEmptyArgs = ["-f", "/dev/null", "if-shell", "-F", "#{==:#{server_sessions},0}", "kill-server"]

    func stopServerIfEmpty() {
        run(Self.stopIfEmptyArgs)
    }

    /// Names the session showing pane `surface` (nil: back to automatic),
    /// then wakes watchers so the phone shows it.
    func setLabel(_ label: String?, surface: UUID, ownedBy pid: Int32) {
        for session in TmuxOwnership.showing(surface, ownedBy: pid, in: sessions()) {
            run(Self.labelArgs(label, sessionID: session.id))
        }
    }

    static func labelArgs(_ label: String?, sessionID: String) -> [String] {
        let clean = label.flatMap(SessionLabel.cleanLabel)
        let set = clean.map { ["set-option", "-t", sessionID, TmuxRemote.labelOption, $0] }
            ?? ["set-option", "-u", "-t", sessionID, TmuxRemote.labelOption]
        return set + [";"] + TmuxHooks.signalCommand
    }

    func isBusy(surface: UUID, ownedBy pid: Int32) -> Bool? {
        guard let out = run(["list-panes", "-a", "-F", TmuxPane.listFormat]) else { return nil }
        return TmuxPane.isBusy(surface, ownedBy: pid, panes: TmuxPane.parseList(out))
    }
}
#endif
