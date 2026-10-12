import Testing
@testable import LosttyRemote

struct TmuxRemoteTests {
    @Test func listFindsTmuxOnAMinimalSSHPath() {
        #expect(TmuxRemote.listCommand.hasPrefix("PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty list-sessions -F "))
    }

    @Test func listKeepsTabsWithoutALocale() {
        #expect(TmuxRemote.listCommand.contains("tmux -u "))
    }

    private static let guardPrefix = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty -f /dev/null display-message -p -t"

    @Test func attachChecksTheNameThenQuotesTheSessionIDAndNeverDetachesOthers() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$3", name: "proj", terminfoDir: "/Applications/Lostty.app/Contents/Resources/terminfo")
        #expect(cmd == "export TERMINFO='/Applications/Lostty.app/Contents/Resources/terminfo'; "
            + "[ \"$(\(Self.guardPrefix) '$3' '#{session_name}' 2>/dev/null)\" = 'proj' ] || exit 1; "
            + "exec env LANG=\"${LANG:-en_US.UTF-8}\" "
            + "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty -f /dev/null attach-session -t '$3'")
        #expect(!cmd.contains(" -d"))
        let export = try #require(cmd.range(of: "export TERMINFO="))
        let guardAt = try #require(cmd.range(of: "display-message"))
        #expect(export.lowerBound < guardAt.lowerBound)
    }

    @Test func attachRefusesAnythingButASessionID() {
        for bad in ["3", "$", "$3;kill-server", "main", "$3 -d", "'$3'"] {
            #expect(throws: TmuxRemoteError.badSessionID(bad)) {
                try TmuxRemote.attachCommand(sessionID: bad, name: "n", terminfoDir: "/t")
            }
        }
    }

    @Test func attachQuotesATerminfoPathWithAQuote() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$1", name: "n", terminfoDir: "/Users/o'brien/Lostty.app/Contents/Resources/terminfo")
        #expect(cmd.contains("TERMINFO='/Users/o'\\''brien/Lostty.app/Contents/Resources/terminfo'"))
    }

    @Test func aNameWithAQuoteIsShellQuotedInTheGuard() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$1", name: "it's; rm -rf ~", terminfoDir: "/t")
        #expect(cmd.contains("= 'it'\\''s; rm -rf ~' ] || exit 1; exec "))
        let kill = try TmuxRemote.killCommand(sessionID: "$1", name: "it's")
        #expect(kill.contains("= 'it'\\''s' ] || exit 1; "))
    }

    @Test func killChecksTheNameThenQuotesTheSessionID() throws {
        #expect(try TmuxRemote.killCommand(sessionID: "$4", name: "proj") ==
            "[ \"$(\(Self.guardPrefix) '$4' '#{session_name}' 2>/dev/null)\" = 'proj' ] || exit 1; "
            + "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty kill-session -t '$4'")
        #expect(throws: TmuxRemoteError.badSessionID("main")) { try TmuxRemote.killCommand(sessionID: "main", name: "n") }
    }

    @Test func sessionsArePickedByProjectName() {
        let s = [
            RemoteSession(id: "$3", name: "zeta", surface: nil, owner: nil),
            RemoteSession(id: "$1", name: "Alpha", surface: nil, owner: nil),
            RemoteSession(id: "$2", name: "beta", surface: "X", owner: 42),
        ]
        #expect(RemoteSession.forPicking(s).map(\.id) == ["$1", "$2", "$3"])
    }

    @Test func parsesTheSessionList() {
        let out = "$1\tlostty\tABCD-1\t4242\n$2\tnotes\t\t\n$3\tmy proj\t\t\n"
        #expect(TmuxRemote.parse(out) == [
            RemoteSession(id: "$1", name: "lostty", surface: "ABCD-1", owner: 4242),
            RemoteSession(id: "$2", name: "notes", surface: nil, owner: nil),
            RemoteSession(id: "$3", name: "my proj", surface: nil, owner: nil),
        ])
    }

    @Test func emptyOrGarbageListIsNoSessions() {
        #expect(TmuxRemote.parse("").isEmpty)
        #expect(TmuxRemote.parse("no server running on /private/tmp/tmux-501/lostty\n").isEmpty)
        #expect(TmuxRemote.parse("1\tx\t\t\n").isEmpty)
    }
}
