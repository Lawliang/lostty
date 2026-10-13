import Foundation
import Testing
@testable import LosttyRemote

struct ClaudeSpinnerTests {
    let seen = Date(timeIntervalSince1970: 1_000)

    @Test func readsClaudesWorkingLine() {
        let line = ClaudeSpinner(line: "✳ Incubating… (3m 51s · ↓ 23.5k tokens)", seenAt: seen)
        #expect(line == ClaudeSpinner(word: "Incubating…", elapsed: 231, detail: "↓ 23.5k tokens", seenAt: seen))
    }

    @Test func readsShorterAndLongerLines() {
        #expect(ClaudeSpinner(line: "✻ Booping…", seenAt: seen) == ClaudeSpinner(word: "Booping…", seenAt: seen))
        #expect(ClaudeSpinner(line: "· Booping… (25s)", seenAt: seen)?.elapsed == 25)
        let busy = ClaudeSpinner(line: "  ✽ Booping… (1h 2m 3s · ↑ 900 tokens · thinking · esc to interrupt)  ", seenAt: seen)
        #expect(busy?.elapsed == 3723)
        #expect(busy?.detail == "↑ 900 tokens · thinking")
        // No time first: all of it is detail.
        #expect(ClaudeSpinner(line: "✶ Booping… (esc to interrupt)", seenAt: seen)?.detail == nil)
        #expect(ClaudeSpinner(line: "✶ Booping… (↓ 3 tokens)", seenAt: seen)?.detail == "↓ 3 tokens")
    }

    @Test func otherLinesAreNotIt() {
        for line in ["", "✳", "✳ Worked for 3m 51s", "⎿  Running…", "> Booping…", "✳Booping…", "✳ …"] {
            #expect(ClaudeSpinner(line: line, seenAt: seen) == nil, "\(line)")
        }
    }

    @Test func theTimeRunsOnFromWhenItWasSeen() {
        let line = ClaudeSpinner(word: "Booping…", elapsed: 55, detail: "↓ 2.0k tokens", seenAt: seen)
        #expect(line.parentheses(now: seen) == "(55s · ↓ 2.0k tokens)")
        #expect(line.parentheses(now: seen.addingTimeInterval(10)) == "(1m 5s · ↓ 2.0k tokens)")
        #expect(line.parentheses(now: seen.addingTimeInterval(3600)) == "(1h 0m 55s · ↓ 2.0k tokens)")
        // A clock that went back never runs the time backwards.
        #expect(line.parentheses(now: seen.addingTimeInterval(-30)) == "(55s · ↓ 2.0k tokens)")
        #expect(line.parentheses(now: seen, detail: false) == "(55s)")
        #expect(ClaudeSpinner(word: "Booping…", seenAt: seen).parentheses(now: seen) == nil)
    }

    @Test func theGlyphGoesUpAndBackDown() {
        #expect((0..<12).map(ClaudeSpinner.glyph) == ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢", "·", "✢"])
        #expect(ClaudeSpinner.glyph(tick: -1) == "✢")
    }

    @Test func onlyAWorkingRowCarriesIt() {
        let spinner = ClaudeSpinner(word: "Booping…", seenAt: seen)
        func row(_ claude: ClaudeActivity?) -> SessionRow {
            SessionLabel.row(
                for: RemoteSession(id: "$1", name: "x", surface: "P", owner: 1, claude: claude, spinner: spinner,
                                   activity: seen),
                now: seen)
        }
        #expect(row(.working).spinner == spinner)
        #expect(row(.subagents).spinner == spinner)
        #expect(row(.waiting).spinner == nil)
        #expect(row(nil).spinner == nil)
    }
}
