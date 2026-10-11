#if os(macOS)
import Foundation

/// Runs `tmux -L lostty …` synchronously. Each call takes a few
/// milliseconds; run it off the main thread except where a decision is
/// needed right away (close confirmation, quitting).
struct TmuxClient {
    /// Homebrew's places first: Lostty started from the Dock has a bare PATH.
    static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]

    var tmuxPath: String? = TmuxClient.locate()

    static func locate(
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let fromPath = (path ?? "").split(separator: ":").map { "\($0)/tmux" }
        return (candidates + fromPath).first(where: isExecutable)
    }

    /// stdout of `tmux -L lostty <args>` when it exits 0; nil when tmux is
    /// missing, no server is running, or the command fails.
    @discardableResult
    func run(_ args: [String]) -> String? {
        guard let tmuxPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = ["-L", TmuxConstants.socket] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
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
