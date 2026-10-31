#if os(macOS)
import Testing
@testable import Lostty

struct RecapTitlesTests {
    @MainActor @Test func aRecapsTitleStandsInForClaudesOwnUnlessTheCardClaimsSomething() {
        #expect(CardController.topic(title: "✳ Handoff open question", claim: nil, recap: "Canvas dock glass restyle")
            == "✳ Canvas dock glass restyle")
        #expect(CardController.topic(title: "◐ Handoff open question", claim: nil, recap: "Canvas dock glass restyle")
            == "◐ Canvas dock glass restyle")
        #expect(CardController.topic(title: "✳ Handoff open question", claim: "recap titles", recap: "Canvas dock")
            == "✳ recap titles")
        // Claude quit: its recap no longer says what the pane does.
        #expect(CardController.topic(title: "zsh", claim: nil, recap: "Canvas dock glass restyle") == "zsh")
    }

    @Test func theLatestRecapIsReadWithoutItsConfigHint() {
        let file = """
        {"type":"system","subtype":"away_summary","content":"We're polishing the dock. (disable recaps in /config)"}
        {"type":"user","message":{"content":"say \\"away_summary\\" here"}}
        {"type":"system","subtype":"away_summary","content":"You're adding recap titles. Next: try it. (disable recaps in /config)"}
        {"type":"system","subtype":"turn_duration"}
        {"type":"user","message":{"content":"the word \\"away_summary\\" in a prompt"}}
        """
        #expect(RecapTitles.latestRecap(in: file) == "You're adding recap titles. Next: try it.")
        #expect(RecapTitles.latestRecap(in: #"{"type":"system","subtype":"turn_duration"}"#) == nil)
    }

    @Test func aLongFileIsReadFromItsEndEvenWhenTheCutSplitsACharacter() throws {
        let recap = #"{"type":"system","subtype":"away_summary","content":"We're adding recap titles."}"#
        let filler = String(repeating: "✳", count: RecapTitles.tailBytes / 3 + 1) + "\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recap-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        // The extra newline moves the cut one byte into a ✳.
        try Data((filler + recap + "\n\n").utf8).write(to: url)
        #expect(RecapTitles.latestRecap(atPath: url.path) == "We're adding recap titles.")
    }

    @Test func anAnswerBecomesItsFirstLineWithoutQuotesOrAPeriod() {
        #expect(RecapTitles.clean("Canvas dock glass restyle") == "Canvas dock glass restyle")
        #expect(RecapTitles.clean("\"Zone ticket board.\"\n") == "Zone ticket board")
        #expect(RecapTitles.clean("**Window Light subagent mode**\nThis names the work.") == "Window Light subagent mode")
        #expect(RecapTitles.clean("  \n") == nil)
        #expect(RecapTitles.clean("Sure, here is a title for the work that this session has been doing") == nil)
    }
}
#endif
