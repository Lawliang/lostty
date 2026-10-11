#if os(macOS)
import Testing
@testable import Ghostty

struct SessionLaunchTests {
    let bin = "/Applications/Lostty.app/Contents/MacOS/ghostty"

    @Test func wrapsAPaneWithoutACommand() {
        #expect(SessionLaunch.command(existing: nil, binary: bin, disabled: false)
            == "'/Applications/Lostty.app/Contents/MacOS/ghostty' +tmux-launch")
        #expect(SessionLaunch.command(existing: "", binary: bin, disabled: false) != nil)
    }

    @Test func keepsAnExplicitCommand() {
        #expect(SessionLaunch.command(existing: "vim notes.md", binary: bin, disabled: false) == nil)
    }

    @Test func offSwitchAndMissingBinaryLeaveThePaneAlone() {
        #expect(SessionLaunch.command(existing: nil, binary: bin, disabled: true) == nil)
        #expect(SessionLaunch.command(existing: nil, binary: nil, disabled: false) == nil)
    }

    @Test func quotesSpacesAndQuotes() {
        #expect(SessionLaunch.shellQuote("/Users/me/My Apps/it's/ghostty")
            == "'/Users/me/My Apps/it'\\''s/ghostty'")
    }

    @Test func attachCommandQuotesTheSessionID() {
        // "$3" unquoted would be expanded by the shell that runs the command.
        #expect(SessionLaunch.attachCommand(binary: "/b/ghostty", sessionID: "$3")
            == "'/b/ghostty' +tmux-launch '--attach=$3'")
    }

    @Test func recognizesItsOwnCommands() {
        #expect(SessionLaunch.isLauncher(SessionLaunch.command(existing: nil, binary: bin, disabled: false)))
        #expect(SessionLaunch.isLauncher(SessionLaunch.attachCommand(binary: bin, sessionID: "$3")))
        #expect(!SessionLaunch.isLauncher(nil))
        #expect(!SessionLaunch.isLauncher("vim"))
        #expect(!SessionLaunch.isLauncher("echo +tmux-launch"))
    }
}
#endif
