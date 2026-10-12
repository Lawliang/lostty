import Foundation
import Testing
@testable import LosttyRemote

struct SessionLabelTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func session(
        _ id: String = "$1", name: String = "lostty", owner: Int32? = 4242, label: String? = nil,
        claude: ClaudeActivity? = nil, title: String = "", path: String = "/Users/me/projectrepos/lostty",
        command: String = "zsh", ago: TimeInterval? = 60
    ) -> RemoteSession {
        RemoteSession(
            id: id, name: name, surface: owner == nil ? nil : "PANE", owner: owner, label: label, claude: claude,
            title: title, path: path, command: command, activity: ago.map { now.addingTimeInterval(-$0) })
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

    @Test func detailLineSaysProjectKindAndMac() {
        #expect(row(session(title: "✳ X", command: "2.1.296")).detail == "lostty · claude · Open on Mac")
        #expect(row(session(owner: nil)).detail == "lostty · shell")
    }

    @Test func waitingAndWorkingOnlyForSessionsOpenOnTheMac() {
        #expect(row(session(claude: .waiting)).status == .waiting)
        #expect(row(session(claude: .waiting)).statusText == "Waiting")
        #expect(row(session(claude: .working)).statusText == "Working")
        #expect(row(session(owner: nil, claude: .waiting, ago: 300)).status == .lastUsed("5m ago"))
    }

    @Test func anOlderMacStillGivesARow() {
        // No @lostty_label / @lostty_claude: tmux prints empty columns.
        let r = row(session(name: "api-2", title: "Lawrences-MacBook.local", path: "/Users/me/api", command: "zsh"))
        #expect(r.title == "api")
        #expect(r.kind == .shell)
        #expect(r.status == .lastUsed("1m ago"))
    }

    @Test func waitingFirstThenMostRecentNotOpenLast() {
        let groups = SessionLabel.ordered([
            session("$1", owner: 1, ago: 10),
            session("$2", owner: nil, ago: 5),
            session("$3", owner: 1, claude: .waiting, ago: 900),
            session("$4", owner: 1, ago: 100),
            session("$5", owner: nil, ago: 50),
            // Not open on the Mac: a leftover "waiting" earns no place at the top.
            session("$6", owner: nil, claude: .waiting, ago: 500),
        ])
        #expect(groups.open.map(\.id) == ["$3", "$1", "$4"])
        #expect(groups.notOpen.map(\.id) == ["$2", "$5", "$6"])
    }

    @Test func tiesFallBackToTheSessionNumber() {
        let groups = SessionLabel.ordered([session("$10", ago: nil), session("$9", ago: nil)])
        #expect(groups.open.map(\.id) == ["$9", "$10"])
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
}
