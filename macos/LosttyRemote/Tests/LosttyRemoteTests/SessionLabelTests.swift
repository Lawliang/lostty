import Foundation
import Testing
@testable import LosttyRemote

struct SessionLabelTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func session(
        _ id: String = "$1", name: String = "lostty", owner: Int32? = 4242, label: String? = nil,
        claude: ClaudeActivity? = nil, action: String? = nil, title: String = "",
        path: String = "/Users/me/projectrepos/lostty", command: String = "zsh", ago: TimeInterval? = 60
    ) -> RemoteSession {
        RemoteSession(
            id: id, name: name, surface: owner == nil ? nil : "PANE", owner: owner, label: label, claude: claude,
            action: action, title: title, path: path, command: command, activity: ago.map { now.addingTimeInterval(-$0) })
    }

    func row(_ s: RemoteSession) -> SessionRow { SessionLabel.row(for: s, now: now) }

    @Test func aTypedNameWinsOverEverything() {
        #expect(row(session(label: "Deploy watch", claude: .working, title: "◐ Fix login", command: "2.1.296")).title == "Deploy watch")
    }

    @Test func aClaudeSessionReadsAsItsTask() {
        let titles = [
            "◐ Lostty UI redesign plan", "◑ Lostty UI redesign plan", "◒ Lostty UI redesign plan",
            "◓ Lostty UI redesign plan", "✳ Lostty UI redesign plan", "✳\u{FE0F} Lostty UI redesign plan",
            "✻ Lostty UI redesign plan", "⠋ Lostty UI redesign plan",
        ]
        for title in titles {
            #expect(row(session(title: title, command: "2.1.296")).title == "Lostty UI redesign plan", "\(title)")
        }
    }

    @Test func aClaudeTitleWithoutAGlyphShowsAsIs() {
        #expect(row(session(claude: .waiting, title: "Lostty UI redesign plan", command: "node")).title == "Lostty UI redesign plan")
    }

    @Test func anEmptyClaudeTitleFallsBackToTheProject() {
        #expect(row(session(claude: .working, title: "✳ ", command: "2.1.296")).title == "lostty")
    }

    @Test func aShellReadsAsItsProject() {
        #expect(row(session(name: "lostty-2", title: "~/projectrepos/lostty", command: "zsh")).title == "lostty")
    }

    @Test func claudeIsTheOptionOrAVersionLikeCommand() {
        #expect(SessionLabel.isClaude(session(command: "2.1.296")))
        #expect(SessionLabel.isClaude(session(claude: .waiting, command: "node")))
        #expect(!SessionLabel.isClaude(session(command: "zsh")))
        #expect(!SessionLabel.isClaude(session(command: "2")))
        #expect(!SessionLabel.isClaude(session(command: "")))
        #expect(!SessionLabel.isClaude(session(command: ".1")))
    }

    @Test func worktreesShowAsRepoSlashName() {
        let base = "/Users/me/projectrepos/lostty/.claude/worktrees/stay-awake"
        #expect(SessionLabel.project(path: base, name: "lostty") == "lostty/stay-awake")
        #expect(SessionLabel.project(path: base + "/", name: "lostty") == "lostty/stay-awake")
        #expect(SessionLabel.project(path: base + "/macos/Sources", name: "lostty") == "lostty/stay-awake")
        #expect(SessionLabel.project(path: "/Users/me/projectrepos/lostty/macos", name: "lostty-3") == "lostty")
        #expect(SessionLabel.project(path: "/Users/me/x/.claude/worktrees/", name: "x") == "x")
        #expect(SessionLabel.project(path: "/.claude/worktrees/a", name: "home") == "home")
    }

    @Test func copyNumbersAreStripped() {
        #expect(SessionLabel.project(path: "", name: "lostty-2") == "lostty")
        #expect(SessionLabel.project(path: "", name: "home-12") == "home")
        #expect(SessionLabel.project(path: "", name: "api-server") == "api-server")
        #expect(SessionLabel.project(path: "", name: "-3") == "-3")
        #expect(SessionLabel.project(path: "", name: "v2-") == "v2-")
    }

    @Test func lastUsedReadsShort() {
        #expect(SessionLabel.relative(now.addingTimeInterval(-20), now: now) == "now")
        #expect(SessionLabel.relative(now.addingTimeInterval(-300), now: now) == "5m ago")
        #expect(SessionLabel.relative(now.addingTimeInterval(-7200), now: now) == "2h ago")
        #expect(SessionLabel.relative(now.addingTimeInterval(-3 * 86400), now: now) == "3d ago")
        #expect(SessionLabel.relative(now.addingTimeInterval(30), now: now) == "now")
        #expect(SessionLabel.relative(nil, now: now) == "")
    }

    @Test func detailLineIsRepoSlashBranch() {
        var s = session(name: "lostty-2", title: "✳ X", command: "2.1.296")
        s.repo = "lostty"
        s.branch = "skins"
        #expect(row(s).detail == "lostty/skins")
        s.owner = nil
        #expect(row(s).detail == "lostty/skins")
    }

    @Test func aWorktreeShowsItsRepoAndBranch() {
        var s = session(path: "/Users/me/projectrepos/lostty/.claude/worktrees/stay-awake")
        s.repo = "lostty"
        s.branch = "main"
        #expect(row(s).detail == "lostty/main")
        #expect(row(s).project == "lostty")
    }

    @Test func withoutABranchTheDetailIsTheProject() {
        #expect(row(session(name: "notes-3", path: "/Users/me/notes")).detail == "notes")
        // Detached, or an older listing: the worktree's name stays.
        var s = session(path: "/Users/me/projectrepos/lostty/.claude/worktrees/stay-awake")
        s.repo = "lostty"
        #expect(row(s).detail == "lostty/stay-awake")
    }

    @Test func theRowCarriesTheSkin() {
        let skin = SessionSkin(encoded: "1c1c1c,,e5199c")
        var s = session()
        s.skin = skin
        #expect(row(s).skin == skin)
        #expect(row(session()).skin == nil)
    }

    @Test func seenAndUsedLatelyIsReadyThenIdle() {
        // Open on the Mac, nothing for Claude to report.
        #expect(row(session(ago: 60)).status == .ready)
        #expect(row(session(ago: 29 * 60)).status == .ready)
        #expect(row(session(ago: 31 * 60)).status == .idle("31m ago"))
        #expect(row(session(ago: 3 * 3600)).status == .idle("3h ago"))
        #expect(row(session(ago: nil)).status == .idle(""))
        #expect(row(session(ago: 60)).statusText == "Ready")
        #expect(row(session(ago: 3 * 3600)).statusText == "3h ago")
        // Waiting and working win however long ago it was used.
        #expect(row(session(claude: .waiting, ago: 3 * 3600)).status == .waiting)
        #expect(row(session(claude: .working, ago: 3 * 3600)).status == .working)
        // No Mac window: only when it was last used.
        #expect(row(session(owner: nil, ago: 60)).status == .lastUsed("1m ago"))
    }

    @Test func onlySubagentsWorkingIsWorking() {
        #expect(row(session(claude: .subagents)).status == .working)
        #expect(TmuxRemote.parse("$1\tx\t\t\t\tagents\t1\tzsh\t/x\t\t\tt\n").first?.claude == .subagents)
    }

    @Test func waitingAndWorkingOnlyForSessionsOpenOnTheMac() {
        #expect(row(session(claude: .waiting)).status == .waiting)
        #expect(row(session(claude: .waiting)).statusText == "Waiting")
        #expect(row(session(claude: .working)).statusText == "Working")
        #expect(row(session(owner: nil, claude: .waiting, ago: 300)).status == .lastUsed("5m ago"))
    }

    @Test func theActionShowsWhileWorkingOrAskingPermission() {
        #expect(row(session(claude: .working, action: "Editing Foo.swift")).action == "Editing Foo.swift")
        #expect(row(session(claude: .subagents, action: "Agent: Find sources")).action == "Agent: Find sources")
        #expect(row(session(claude: .waiting, action: "Run the tests")).action == "Allow? Run the tests")
        #expect(row(session(claude: .working)).action == nil)
        // Not for a terminal no Mac window shows, nor one Claude isn't working in.
        #expect(row(session(owner: nil, claude: .working, action: "Editing Foo.swift")).action == nil)
        #expect(row(session(action: "Editing Foo.swift")).action == nil)
    }

    @Test func anOlderMacStillGivesARow() {
        // No @lostty_label / @lostty_claude: tmux prints empty columns.
        let r = row(session(name: "api-2", title: "Lawrences-MacBook.local", path: "/Users/me/api", command: "zsh"))
        #expect(r.title == "api")
        #expect(r.kind == .shell)
        #expect(r.status == .ready)
    }

    @Test func activeWaitingFirstThenMostRecentInactiveApart() {
        let groups = SessionLabel.ordered([
            session("$1", owner: 1, ago: 10),
            session("$2", owner: nil, ago: 5),
            session("$3", owner: 1, claude: .waiting, ago: 900),
            session("$4", owner: 1, ago: 100),
            session("$5", owner: nil, ago: 50),
            // Not open on the Mac: a leftover "waiting" earns no place at the top.
            session("$6", owner: nil, claude: .waiting, ago: 500),
        ])
        #expect(groups.active.map(\.id) == ["$3", "$1", "$4"])
        // No Mac window: a leftover "waiting" earns no place at the top.
        #expect(groups.inactive.map(\.id) == ["$2", "$5", "$6"])
    }

    @Test func tiesFallBackToTheSessionNumber() {
        let groups = SessionLabel.ordered([session("$10", ago: nil), session("$9", ago: nil)])
        #expect(groups.active.map(\.id) == ["$9", "$10"])
    }

    @Test func typedNamesLoseControlCharactersAndTrailingSemicolons() {
        #expect(SessionLabel.cleanLabel("  Deploy\twatch\n") == "Deploy watch")
        #expect(SessionLabel.cleanLabel("x;") == "x")
        #expect(SessionLabel.cleanLabel("a ; ;") == "a")
        #expect(SessionLabel.cleanLabel(";") == nil)
        #expect(SessionLabel.cleanLabel("   ") == nil)
        #expect(SessionLabel.cleanLabel("👩‍💻 pair") == "👩‍💻 pair")
        #expect(SessionLabel.cleanLabel(String(repeating: "a", count: 100))?.count == 80)
    }

    @Test func closingWarnsItEndsOnThePhoneAndTheMac() {
        let open = SessionLabel.closeWarning(for: session(label: "Deploy watch"))
        #expect(open.title == "Close \u{201C}Deploy watch\u{201D}?")
        #expect(open.message.contains("both your phone and your Mac"))
        let noWindow = SessionLabel.closeWarning(for: session(owner: nil))
        #expect(noWindow.title == "Close \u{201C}lostty\u{201D}?")
        #expect(noWindow.message.contains("on your phone and ends it on your Mac"))
        #expect(noWindow.message.contains("without a window"))
    }
}
