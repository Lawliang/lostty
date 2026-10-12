import Testing
@testable import LosttyRemote

struct TmuxRemoteTests {
    @Test func listFindsTmuxOnAMinimalSSHPath() {
        #expect(TmuxRemote.listCommand.hasPrefix("PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty list-sessions -F "))
    }

    @Test func listKeepsTabsWithoutALocale() {
        #expect(TmuxRemote.listCommand.contains("tmux -u "))
    }

    @Test func attachQuotesTheSessionIDAndNeverDetachesOthers() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$3", terminfoDir: "/Applications/Lostty.app/Contents/Resources/terminfo")
        #expect(cmd == "exec env LANG=\"${LANG:-en_US.UTF-8}\" TERMINFO='/Applications/Lostty.app/Contents/Resources/terminfo' "
            + "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty -f /dev/null attach-session -t '$3'")
        #expect(!cmd.contains(" -d"))
    }

    @Test func attachRefusesAnythingButASessionID() {
        for bad in ["3", "$", "$3;kill-server", "main", "$3 -d", "'$3'"] {
            #expect(throws: TmuxRemoteError.badSessionID(bad)) {
                try TmuxRemote.attachCommand(sessionID: bad, terminfoDir: "/t")
            }
        }
    }

    @Test func attachQuotesATerminfoPathWithAQuote() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$1", terminfoDir: "/Users/o'brien/Lostty.app/Contents/Resources/terminfo")
        #expect(cmd.contains("TERMINFO='/Users/o'\\''brien/Lostty.app/Contents/Resources/terminfo'"))
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
