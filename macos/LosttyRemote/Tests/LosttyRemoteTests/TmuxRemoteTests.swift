import Foundation
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

    private static let tmux = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH tmux -u -L lostty"

    private static func nameGuard(_ id: String, _ name: String) -> String {
        "[ \"$(\(guardPrefix) '\(id)' '#{session_name}' 2>/dev/null)\" = '\(name)' ] || exit 1; "
    }

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
        let kill = try TmuxRemote.killCommand(sessionID: "$1", name: "it's", device: "iPhone")
        #expect(kill.contains("= 'it'\\''s' ] || exit 1; "))
    }

    @Test func killChecksTheNameThenTagsTheEndAndKills() throws {
        #expect(try TmuxRemote.killCommand(sessionID: "$4", name: "proj", device: "iPhone 15 Pro") ==
            Self.nameGuard("$4", "proj")
            + "\(Self.tmux) set-option -g @lostty_end_4 'phone:iPhone 15 Pro' \\; kill-session -t '$4'")
        #expect(throws: TmuxRemoteError.badSessionID("main")) {
            try TmuxRemote.killCommand(sessionID: "main", name: "n", device: "iPhone")
        }
    }

    @Test func aDeviceNameWithAQuoteIsQuoted() throws {
        let kill = try TmuxRemote.killCommand(sessionID: "$4", name: "p", device: "Alex's iPhone")
        #expect(kill.contains("@lostty_end_4 'phone:Alex'\\''s iPhone' \\; "))
    }

    @Test func renameSetsTheLabelThenSignals() throws {
        #expect(try TmuxRemote.renameCommand(sessionID: "$4", name: "proj", label: "Deploy watch") ==
            Self.nameGuard("$4", "proj")
            + "\(Self.tmux) set-option -t '$4' @lostty_label 'Deploy watch' \\; wait-for -S lostty-changed")
    }

    @Test func renameToNothingClearsTheLabel() throws {
        #expect(try TmuxRemote.renameCommand(sessionID: "$4", name: "proj", label: nil) ==
            Self.nameGuard("$4", "proj")
            + "\(Self.tmux) set-option -u -t '$4' @lostty_label \\; wait-for -S lostty-changed")
    }

    @Test func renameQuotesTheLabelAndRefusesBadIDs() throws {
        let cmd = try TmuxRemote.renameCommand(sessionID: "$4", name: "p", label: "x'; rm -rf ~")
        #expect(cmd.contains("@lostty_label 'x'\\''; rm -rf ~' \\; "))
        #expect(throws: TmuxRemoteError.badSessionID("$4;x")) {
            try TmuxRemote.renameCommand(sessionID: "$4;x", name: "p", label: "x")
        }
    }

    @Test func renameCleansTheLabelSoATrailingSemicolonIsNotACommandSeparator() throws {
        let cmd = try TmuxRemote.renameCommand(sessionID: "$4", name: "p", label: "build;")
        #expect(cmd.contains("@lostty_label 'build' \\; wait-for"))
        #expect(!cmd.contains("build;'"))
        // A label with nothing left clears it.
        #expect(try TmuxRemote.renameCommand(sessionID: "$4", name: "p", label: " ; ")
            == TmuxRemote.renameCommand(sessionID: "$4", name: "p", label: nil))
    }

    @Test func theEndProbeReadsTheTagAndWhetherTheSessionIsThere() throws {
        #expect(try TmuxRemote.endProbeCommand(sessionID: "$7") ==
            "T=$(\(Self.tmux) -f /dev/null show-options -gqv '@lostty_end_7' 2>/dev/null); "
            + "if \(Self.tmux) -f /dev/null has-session -t '$7' 2>/dev/null; then echo present; else echo gone; fi; "
            + "printf '%s\\n' \"$T\"")
    }

    @Test func parsesTheEndProbe() {
        #expect(TmuxRemote.parseEndProbe("gone\nmac-close\n") == EndProbe(exists: false, tag: "mac-close"))
        #expect(TmuxRemote.parseEndProbe("present\n\n") == EndProbe(exists: true, tag: nil))
        #expect(TmuxRemote.parseEndProbe("gone\n") == EndProbe(exists: false, tag: nil))
        #expect(TmuxRemote.parseEndProbe("") == nil)
        #expect(TmuxRemote.parseEndProbe("no server running\n") == nil)
    }

    @Test func theWatchLoopsOnTheChannelWithoutStartingAServer() {
        #expect(TmuxRemote.watchCommand == "while \(Self.tmux) -f /dev/null wait-for lostty-changed; do echo; done")
    }

    @Test func eachSessionHasItsOwnEndOption() throws {
        #expect(try TmuxRemote.endOption(sessionID: "$12") == "@lostty_end_12")
        #expect(throws: TmuxRemoteError.badSessionID("12")) { try TmuxRemote.endOption(sessionID: "12") }
    }

    @Test func listsAreAtLeast300msApart() {
        let t = Date(timeIntervalSince1970: 100)
        #expect(ListPacing.delay(sinceLastList: t, now: t) == 0.3)
        #expect(abs(ListPacing.delay(sinceLastList: t, now: t.addingTimeInterval(0.1)) - 0.2) < 0.0001)
        #expect(ListPacing.delay(sinceLastList: t, now: t.addingTimeInterval(1)) == 0)
        #expect(ListPacing.delay(sinceLastList: .distantPast, now: t) == 0)
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
        let out = "$1\tlostty\tABCD-1\t4242\tDeploy\twaiting\t1700000000\t2.1.296\t/Users/me/lostty\t✳ Fix login\n"
            + "$2\tnotes\t\t\t\t\t\tzsh\t/Users/me/notes\t~/notes\n"
        #expect(TmuxRemote.parse(out) == [
            RemoteSession(
                id: "$1", name: "lostty", surface: "ABCD-1", owner: 4242, label: "Deploy", claude: .waiting,
                title: "✳ Fix login", path: "/Users/me/lostty", command: "2.1.296",
                activity: Date(timeIntervalSince1970: 1_700_000_000)),
            RemoteSession(
                id: "$2", name: "notes", surface: nil, owner: nil, label: nil, claude: nil,
                title: "~/notes", path: "/Users/me/notes", command: "zsh", activity: nil),
        ])
    }

    @Test func aTabInTheTitleStaysInTheTitle() {
        let out = "$1\tx\t\t\t\t\t1\tzsh\t/x\tleft\tright 🚀\n"
        #expect(TmuxRemote.parse(out).first?.title == "left\tright 🚀")
    }

    @Test func theListAsksForEveryColumnTitleLast() {
        #expect(TmuxRemote.listFormat == "#{session_id}\t#{session_name}\t#{@lostty_surface}\t#{@lostty_owner}\t"
            + "#{@lostty_label}\t#{@lostty_claude}\t#{session_activity}\t#{pane_current_command}\t"
            + "#{pane_current_path}\t#{pane_title}")
    }

    @Test func anUnknownClaudeValueIsNone() {
        #expect(TmuxRemote.parse("$1\tx\t\t\t\tthinking\t1\tzsh\t/x\tt\n").first?.claude == nil)
    }

    @Test func emptyOrGarbageListIsNoSessions() {
        #expect(TmuxRemote.parse("").isEmpty)
        #expect(TmuxRemote.parse("no server running on /private/tmp/tmux-501/lostty\n").isEmpty)
        #expect(TmuxRemote.parse("1\tx\t\t\n").isEmpty)
    }

    @Test func attachWithoutATerminfoPathExportsNothing() throws {
        let cmd = try TmuxRemote.attachCommand(sessionID: "$3", name: "proj", terminfoDir: nil)
        #expect(!cmd.contains("TERMINFO"))
        #expect(cmd.hasPrefix("[ \"$("))
        #expect(cmd.hasSuffix("attach-session -t '$3'"))
    }
}
