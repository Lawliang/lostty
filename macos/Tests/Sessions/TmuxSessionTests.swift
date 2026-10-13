#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

private let paneA = UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000001")!
private let paneB = UUID(uuidString: "ABCDEF02-0000-4000-8000-000000000002")!

struct TmuxSessionTests {
    @Test func parsesList() {
        let out = "$1\tidfk\t\(paneA.uuidString)\t4242\n$2\tnotes\t\t\n$3\tmy proj\t\t\n"
        #expect(TmuxSession.parseList(out) == [
            TmuxSession(id: "$1", name: "idfk", surface: paneA.uuidString, owner: 4242),
            TmuxSession(id: "$2", name: "notes", surface: nil, owner: nil),
            TmuxSession(id: "$3", name: "my proj", surface: nil, owner: nil),
        ])
    }

    @Test func skipsMalformedLines() {
        #expect(TmuxSession.parseList("garbage\n\n1\tx\t\t\n$4\t\t\t\n").isEmpty)
    }
}

struct TmuxOwnershipTests {
    // 100 is this Lostty, 200 a Debug build running next to it, 300 crashed.
    let alive: (Int32) -> Bool = { $0 == 100 || $0 == 200 }
    let sessions = [
        TmuxSession(id: "$1", name: "a", surface: paneA.uuidString, owner: 100),
        TmuxSession(id: "$2", name: "b", surface: paneB.uuidString, owner: 200),
        // The crashed Lostty's session for a window that was restored with
        // the same pane UUID.
        TmuxSession(id: "$3", name: "c", surface: paneA.uuidString, owner: 300),
        // Made on the phone.
        TmuxSession(id: "$4", name: "d", surface: nil, owner: nil),
    ]

    @Test func orphansAreOwnedByLosttysThatAreGone() {
        #expect(TmuxOwnership.orphans(sessions, isAlive: alive).map(\.id) == ["$3"])
    }

    @Test func aRunningSecondLosttyIsNotAnOrphan() {
        #expect(!TmuxOwnership.orphans(sessions, isAlive: alive).contains { $0.id == "$2" })
    }

    @Test func quitEndsOnlyOwnSessions() {
        #expect(TmuxOwnership.owned(by: 100, in: sessions).map(\.id) == ["$1"])
    }

    @Test func availableIsWhatNoRunningLosttyShows() {
        #expect(TmuxOwnership.available(sessions, isAlive: alive).map(\.id) == ["$3", "$4"])
    }

    @Test func aRestoredWindowsSessionIsNotOfferedAgain() {
        // macOS restored $3's window (same pane id); its launcher adopts $3.
        let orphans = TmuxOwnership.orphans(sessions, isAlive: alive)
        #expect(TmuxOwnership.reopenable(orphans, openPanes: [paneA]).isEmpty)
        #expect(TmuxOwnership.reopenable(orphans, openPanes: [paneB]).map(\.id) == ["$3"])
    }

    @Test func closingAPaneEndsOnlyThisLosttysSession() {
        #expect(TmuxOwnership.showing(paneA, ownedBy: 100, in: sessions).map(\.id) == ["$1"])
    }
}

struct TmuxPaneTests {
    @Test func atThePromptIsNotBusy() {
        let panes = TmuxPane.parseList("\(paneA.uuidString)\t100\tzsh\tzsh\n")
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: panes) == false)
    }

    @Test func claudeRunningIsBusy() {
        let panes = TmuxPane.parseList("\(paneA.uuidString)\t100\tclaude\tzsh\n")
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: panes) == true)
    }

    @Test func unknownDefersToTheCore() {
        // No pane for this surface, or a session without a recorded shell.
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: []) == nil)
        let noShell = TmuxPane.parseList("\(paneA.uuidString)\t100\tzsh\t\n")
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: noShell) == nil)
    }

    @Test func otherLosttysPaneIsIgnored() {
        let panes = TmuxPane.parseList(
            "\(paneA.uuidString)\t300\tclaude\tzsh\n\(paneA.uuidString)\t100\tzsh\tzsh\n")
        #expect(TmuxPane.isBusy(paneA, ownedBy: 100, panes: panes) == false)
    }

    @Test func skipsPanesWithoutASurface() {
        #expect(TmuxPane.parseList("\t\tzsh\tzsh\n").isEmpty)
    }
}

final class TmuxClientTests {
    /// Stand-in tmux scripts this test wrote; removed when it ends.
    private var fakes: [URL] = []

    deinit {
        fakes.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    @Test func locatePrefersHomebrewOverABarePATH() {
        let found = TmuxClient.locate(path: "/usr/bin:/bin") {
            $0 == "/opt/homebrew/bin/tmux" || $0 == "/usr/bin/tmux"
        }
        #expect(found == "/opt/homebrew/bin/tmux")
    }

    @Test func renamingSetsOrClearsTheLabelThenSignals() {
        #expect(TmuxClient.labelArgs("Deploy", sessionID: "$3")
            == ["set-option", "-t", "$3", "@lostty_label", "Deploy", ";", "wait-for", "-S", "lostty-changed"])
        #expect(TmuxClient.labelArgs(nil, sessionID: "$3")
            == ["set-option", "-u", "-t", "$3", "@lostty_label", ";", "wait-for", "-S", "lostty-changed"])
    }

    @Test func aLabelEndingInASemicolonCannotBecomeASeparator() {
        #expect(TmuxClient.labelArgs("Deploy;", sessionID: "$3")
            == ["set-option", "-t", "$3", "@lostty_label", "Deploy", ";", "wait-for", "-S", "lostty-changed"])
        // Nothing left after cleaning: clears the label instead.
        #expect(TmuxClient.labelArgs(";", sessionID: "$3")
            == ["set-option", "-u", "-t", "$3", "@lostty_label", ";", "wait-for", "-S", "lostty-changed"])
    }

    @Test func locateFallsBackToPATH() {
        #expect(TmuxClient.locate(path: "/usr/bin:/custom/bin") { $0 == "/custom/bin/tmux" } == "/custom/bin/tmux")
    }

    @Test func locateReportsMissingTmux() {
        #expect(TmuxClient.locate(path: "/usr/bin:/bin") { _ in false } == nil)
    }

    @Test func missingTmuxMeansNoSessionsAndNoAnswer() {
        let client = TmuxClient(tmuxPath: nil)
        #expect(client.sessions().isEmpty)
        #expect(client.isBusy(surface: paneA, ownedBy: 100) == nil)
    }

    /// A stand-in tmux: a shell script with `body`.
    private func fakeTmux(_ body: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-tmux-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        fakes.append(url)
        return url.path
    }

    @Test func runReturnsStdoutOnSuccess() throws {
        // Room for macOS's first-run scan of the new script under load.
        let client = TmuxClient(tmuxPath: try fakeTmux("echo \"$@\""), timeout: 10)
        #expect(client.run(["list-sessions"]) == "-u -L lostty list-sessions\n")
    }

    @Test func runReportsFailure() throws {
        let client = TmuxClient(tmuxPath: try fakeTmux("echo out; exit 1"))
        #expect(client.run(["list-sessions"]) == nil)
    }

    /// A stand-in tmux that lists `sessions` (4 columns) and appends every
    /// other call's arguments to `log`.
    private func loggingTmux(sessions: String, log: URL) throws -> TmuxClient {
        TmuxClient(tmuxPath: try fakeTmux("""
            if [ "$4" = list-sessions ]; then printf '\(sessions)'; exit 0; fi
            echo "$@" >> '\(log.path)'
            """), timeout: 10)
    }

    private func tempLog() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-tmux-log-\(UUID().uuidString)")
        fakes.append(url)
        return url
    }

    @Test func quittingTagsEachOwnSessionBeforeEndingIt() throws {
        let log = tempLog()
        let client = try loggingTmux(sessions: "$3\\tlostty\\t\(paneA.uuidString)\\t100\\n$4\\tnotes\\t\\t200\\n", log: log)
        client.endSessions(ownedBy: 100)
        #expect(try String(contentsOf: log, encoding: .utf8)
            == "-u -L lostty set-option -g @lostty_end_3 mac-quit ; kill-session -t $3\n")
    }

    @Test func closingAPaneTagsItsSessionMacClose() throws {
        let log = tempLog()
        let client = try loggingTmux(sessions: "$5\\tapi\\t\(paneA.uuidString)\\t100\\n", log: log)
        client.endSessions(showing: paneA, ownedBy: 100)
        #expect(try String(contentsOf: log, encoding: .utf8)
            == "-u -L lostty set-option -g @lostty_end_5 mac-close ; kill-session -t $5\n")
    }

    @Test func aBadIDIsKilledWithoutATag() {
        let odd = TmuxSession(id: "$x", name: "n", surface: nil, owner: nil)
        #expect(TmuxClient.endArgs(odd, reason: "mac-close") == ["kill-session", "-t", "$x"])
    }

    @Test func signallingNeverStartsAServerWithTheUsersConfig() throws {
        let log = tempLog()
        let client = try loggingTmux(sessions: "", log: log)
        client.signalChanged()
        #expect(try String(contentsOf: log, encoding: .utf8) == "-u -L lostty -f /dev/null wait-for -S lostty-changed\n")
    }

    @Test func launchStopsOnlyAnEmptyServerAndNeverStartsOne() throws {
        let log = tempLog()
        let client = try loggingTmux(sessions: "", log: log)
        client.stopServerIfEmpty()
        // One command, decided inside tmux: a session made meanwhile (a
        // restored window) can't be caught between a check and the kill.
        #expect(try String(contentsOf: log, encoding: .utf8)
            == "-u -L lostty -f /dev/null if-shell -F #{==:#{server_sessions},0} kill-server\n")
    }

    @Test func disowningAlsoClearsTheClaudeStateThenSignals() throws {
        let log = tempLog()
        let client = try loggingTmux(sessions: "", log: log)
        client.disown(TmuxSession(id: "$3", name: "api", surface: paneA.uuidString, owner: 300))
        #expect(try String(contentsOf: log, encoding: .utf8)
            == "-u -L lostty set-option -u -t $3 @lostty_surface ; set-option -u -t $3 @lostty_owner ; "
            + "set-option -u -t $3 @lostty_claude ; wait-for -S lostty-changed\n")
    }

    @Test func remoteSessionsAskForThePhonesColumns() throws {
        let client = TmuxClient(tmuxPath: try fakeTmux("""
            [ "$6" = '\(TmuxRemote.listFormat)' ] || exit 1
            printf '$1\\tlostty\\t\\t\\tDeploy\\twaiting\\t100\\t2.1.296\\t/x\\t\\t\\t✳ Fix login\\n'
            """), timeout: 10)
        let found = client.remoteSessions()
        #expect(found.map(\.label) == ["Deploy"])
        #expect(found.first?.claude == .waiting)
    }

    @Test func aHungTmuxGivesUpAtTheTimeout() throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-tmux-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        // Long enough for macOS's first-run scan of the new script (~1 s).
        let client = TmuxClient(tmuxPath: try fakeTmux("echo $$ > '\(pidFile.path)'; exec sleep 30"), timeout: 3)
        let start = Date()
        #expect(client.run(["list-sessions"]) == nil)
        #expect(Date().timeIntervalSince(start) < 6)
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        // Killed and reaped (a zombie still answers kill(pid, 0)).
        var gone = false
        for _ in 0..<20 where !gone {
            gone = kill(pid, 0) != 0
            if !gone { usleep(50_000) }
        }
        #expect(gone, "the hung tmux is still running")
    }
}
#endif
