#if os(macOS)
import Testing
@testable import Lostty

struct SessionsPromptTests {
    @Test func oneSession() {
        let text = SessionsPrompt.reopen([TmuxSession(id: "$1", name: "idfk", surface: "S", owner: 9)])
        #expect(text.title == "Reopen 1 terminal session?")
        #expect(text.body.contains("idfk"))
    }

    @Test func severalSessionsAreNamed() {
        let text = SessionsPrompt.reopen([
            TmuxSession(id: "$1", name: "idfk", surface: "S", owner: 9),
            TmuxSession(id: "$2", name: "notes", surface: "T", owner: 9),
        ])
        #expect(text.title == "Reopen 2 terminal sessions?")
        #expect(text.body.contains("idfk, notes"))
        // Says what Not Now does.
        #expect(text.body.contains("Not Now"))
    }
}
#endif
