#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

/// One tmux call reads every working pane's screen, and each pane's last
/// working-looking line says whether Claude still works there.
struct ClaudeWorkingLineWatchTests {
    let a = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let b = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    @Test func oneCallNamesAndCapturesEachPane() {
        let args = ClaudeWorkingLineWatch.args([(pane: a, session: "$1"), (pane: b, session: "$7")])
        #expect(args == [
            "display-message", "-p", "-t", "$1", "@@lostty-pane \(a.uuidString)", ";",
            "capture-pane", "-pJ", "-t", "$1", ";",
            "display-message", "-p", "-t", "$7", "@@lostty-pane \(b.uuidString)", ";",
            "capture-pane", "-pJ", "-t", "$7",
        ])
    }

    @Test func aPaneShowsTheLineOnlyWhileItsScreenHasIt() {
        let output = """
            @@lostty-pane \(a.uuidString)
            ⏺ Reading the file
              ✳ Incubating… (3m 51s · esc to interrupt)
            > 
            @@lostty-pane \(b.uuidString)
            ⏺ Done.
            > 
            """
        #expect(ClaudeWorkingLineWatch.showing(output) == [a: true, b: false])
    }

    @Test func theLastWorkingLookingLineDecides() {
        let output = """
            @@lostty-pane \(a.uuidString)
            ✳ Incubating… (2s)
            · said… and then stopped
            """
        #expect(ClaudeWorkingLineWatch.showing(output) == [a: false])
    }

    @Test func aPaneTmuxDidNotPrintIsUnknown() {
        #expect(ClaudeWorkingLineWatch.showing("") == [:])
    }
}
#endif
