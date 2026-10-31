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
        let url = try conversation(filler + recap + "\n\n")
        defer { try? FileManager.default.removeItem(at: url) }
        // The extra newline moves the cut one byte into a ✳.
        #expect(RecapTitles.readRecap(atPath: url.path, from: nil)?.recap == "We're adding recap titles.")
    }

    @Test func laterReadsSeeOnlyWhatWasAddedAndWaitForAHalfWrittenLine() throws {
        let first = #"{"type":"system","subtype":"away_summary","content":"We're planning pantry."}"# + "\n"
        let url = try conversation(first)
        defer { try? FileManager.default.removeItem(at: url) }
        let start = try #require(RecapTitles.readRecap(atPath: url.path, from: nil))
        #expect(start == RecapRead(recap: "We're planning pantry.", end: UInt64(first.utf8.count)))

        let file = try FileHandle(forWritingTo: url)
        try file.seekToEnd()
        try file.write(contentsOf: Data(#"{"type":"user"}"#.utf8) + Data("\n".utf8))
        let quiet = try #require(RecapTitles.readRecap(atPath: url.path, from: start.end))
        #expect(quiet.recap == nil)

        let next = #"{"type":"system","subtype":"away_summary","content":"We're adding --days."}"#
        try file.write(contentsOf: Data(next.prefix(30).utf8))
        let half = try #require(RecapTitles.readRecap(atPath: url.path, from: quiet.end))
        #expect(half == RecapRead(recap: nil, end: quiet.end))

        try file.write(contentsOf: Data((next.dropFirst(30) + "\n").utf8))
        try file.close()
        #expect(RecapTitles.readRecap(atPath: url.path, from: half.end)?.recap == "We're adding --days.")
    }

    @Test func aFileShorterThanWhereReadingGotToIsReadAfresh() throws {
        let url = try conversation(#"{"type":"system","subtype":"away_summary","content":"We're starting over."}"# + "\n")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(RecapTitles.readRecap(atPath: url.path, from: 1_000_000)?.recap == "We're starting over.")
    }

    private func conversation(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recap-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: url)
        return url
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
