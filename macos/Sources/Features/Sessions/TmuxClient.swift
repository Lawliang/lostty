#if os(macOS)
import Foundation

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
        process.arguments = ["-L", TmuxConstants.socket] + args
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

        // Read while it runs, so a full pipe can't stall it.
        let output = Output()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
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

    func end(_ session: TmuxSession) {
        run(["kill-session", "-t", session.id])
    }

    /// Ends the session showing pane `surface`: closing a pane ends its
    /// shell, as on a plain terminal.
    func endSessions(showing surface: UUID, ownedBy pid: Int32) {
        TmuxOwnership.showing(surface, ownedBy: pid, in: sessions()).forEach(end)
    }

    /// Ends every session Lostty `pid` shows: quitting ends its shells.
    func endSessions(ownedBy pid: Int32) {
        TmuxOwnership.owned(by: pid, in: sessions()).forEach(end)
    }

    /// Lets go of a session: no Lostty shows it any more, so it is not
    /// offered after a crash again; it stays running for the phone and
    /// for Open Session.
    func disown(_ session: TmuxSession) {
        run(["set-option", "-u", "-t", session.id, TmuxConstants.surfaceOption, ";",
             "set-option", "-u", "-t", session.id, TmuxConstants.ownerOption])
    }

    func isBusy(surface: UUID, ownedBy pid: Int32) -> Bool? {
        guard let out = run(["list-panes", "-a", "-F", TmuxPane.listFormat]) else { return nil }
        return TmuxPane.isBusy(surface, ownedBy: pid, panes: TmuxPane.parseList(out))
    }
}
#endif
