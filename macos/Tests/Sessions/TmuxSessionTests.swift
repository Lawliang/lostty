#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

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

struct TmuxClientTests {
    @Test func locatePrefersHomebrewOverABarePATH() {
        let found = TmuxClient.locate(path: "/usr/bin:/bin") {
            $0 == "/opt/homebrew/bin/tmux" || $0 == "/usr/bin/tmux"
        }
        #expect(found == "/opt/homebrew/bin/tmux")
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
        return url.path
    }

    @Test func runReturnsStdoutOnSuccess() throws {
        let client = TmuxClient(tmuxPath: try fakeTmux("echo \"$@\""))
        #expect(client.run(["list-sessions"]) == "-L lostty list-sessions\n")
    }

    @Test func runReportsFailure() throws {
        let client = TmuxClient(tmuxPath: try fakeTmux("echo out; exit 1"))
        #expect(client.run(["list-sessions"]) == nil)
    }

    @Test func aHungTmuxGivesUpAtTheTimeout() throws {
        let client = TmuxClient(tmuxPath: try fakeTmux("sleep 30"), timeout: 0.3)
        let start = Date()
        #expect(client.run(["list-sessions"]) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }
}
#endif
