#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ObserverPromptTests {
    func words(_ word: String, _ count: Int) -> String {
        Array(repeating: word, count: count).joined(separator: " ")
    }

    @Test func aFirstRunHasNoNotesYet() {
        let prompt = ObserverPrompt.build(
            previous: nil,
            earlier: [ConversationEntry(speaker: .you, text: "Fix the login bug")],
            lastReply: "Fixed it.", words: ObserverPrompt.cliWords)
        #expect(prompt.contains("Your notes so far:\n(none yet)"))
        #expect(prompt.contains("You: Fix the login bug"))
        #expect(prompt.contains("The agent's last reply:\nFixed it."))
        for key in ["why", "asked", "decided", "built", "progress", "left", "just_now"] {
            #expect(prompt.contains("\"\(key)\""))
        }
    }

    @Test func laterRunsCarryTheNotes() {
        let previous = ObserverNotes(why: "Login was broken.", built: ["Fixed the login bug"], justNow: "Fixed.")
        let prompt = ObserverPrompt.build(
            previous: previous,
            earlier: [ConversationEntry(speaker: .you, text: "Now add tests"),
                      ConversationEntry(speaker: .agent, text: "Sure")],
            lastReply: "Added two tests.", words: ObserverPrompt.cliWords)
        #expect(prompt.contains(#""built":["Fixed the login bug"]"#))
        #expect(prompt.contains(#""why":"Login was broken.""#))
        #expect(prompt.contains("You: Now add tests\n\nAgent: Sure"))
    }

    @Test func nothingNewSaysSo() {
        let prompt = ObserverPrompt.build(previous: ObserverNotes(justNow: "x"), earlier: [], lastReply: "", words: 100)
        #expect(prompt.contains("Conversation since then:\n(nothing new)"))
        #expect(prompt.contains("The agent's last reply:\n(none)"))
    }

    @Test func theOldestEntriesGoFirst() {
        // 40 words: the reply takes 10, the context the newest 30.
        let earlier = (0..<4).map { ConversationEntry(speaker: .you, text: words("alpha\($0)", 10)) }
        let prompt = ObserverPrompt.build(previous: nil, earlier: earlier, lastReply: words("reply", 10), words: 40)
        #expect(!prompt.contains("alpha0"))
        #expect(prompt.contains("alpha1") && prompt.contains("alpha2") && prompt.contains("alpha3"))
    }

    @Test func anEntryThatDoesntFitKeepsItsEnd() {
        // Tokens that never appear in the prompt's own instructions.
        let entry = ConversationEntry(speaker: .agent, text: words("qqq", 5) + " " + words("zzz", 10))
        let prompt = ObserverPrompt.build(previous: nil, earlier: [entry], lastReply: "", words: 10)
        #expect(prompt.contains("Agent: … " + words("zzz", 10)))
        #expect(!prompt.contains("qqq"))
    }

    @Test func aLongReplyTakesAtMostHalf() {
        let prompt = ObserverPrompt.build(
            previous: nil, earlier: [ConversationEntry(speaker: .you, text: "go")],
            lastReply: words("start", 50) + " " + words("end", 50), words: 100)
        #expect(prompt.contains("The agent's last reply:\n… " + words("end", 50)))
        #expect(prompt.contains("You: go"))
    }

    @Test func aLongConversationIsCutToTheNewestWords() {
        let earlier = (0..<400).map { ConversationEntry(speaker: $0.isMultiple(of: 2) ? .you : .agent, text: words("w\($0)", 100)) }
        let prompt = ObserverPrompt.build(previous: nil, earlier: earlier, lastReply: words("reply", 100),
                                          words: ObserverPrompt.cliWords)
        let header = ObserverPrompt.build(previous: nil, earlier: [], lastReply: "", words: ObserverPrompt.cliWords)
        // Plus one "You:"/"Agent:" label per entry kept (at most 300) and the "…" of a cut.
        #expect(ObserverPrompt.wordCount(prompt) <= ObserverPrompt.cliWords + ObserverPrompt.wordCount(header) + 301)
        #expect(prompt.contains("w399"))
        #expect(!prompt.contains("w0 "))
    }

    @Test func parsesTheReply() {
        let reply = #"""
        {"why":"Login was broken.","asked":["Fix login"],"decided":["Look: keep the old screen"],
         "built":["Fixed login"],"progress":"done","left":["Add tests"],"just_now":"It works now."}
        """#
        #expect(ObserverPrompt.parse(reply) == ObserverNotes(
            why: "Login was broken.", asked: ["Fix login"], decided: ["Look: keep the old screen"],
            built: ["Fixed login"], progress: "done", left: ["Add tests"], justNow: "It works now."))
    }

    @Test func parsesAFencedOrIntroducedReply() {
        // Missing keys are empty; list markers and blank bullets are dropped.
        let fenced = "```json\n{\"built\": [\"- Fixed login\", \"  \"], \"just_now\": \" It works. \"}\n```"
        #expect(ObserverPrompt.parse(fenced) == ObserverNotes(built: ["Fixed login"], justNow: "It works."))
        #expect(ObserverPrompt.parse("Here you go: {\"just_now\":\"Hi\"}") == ObserverNotes(justNow: "Hi"))
    }

    @Test func asksForShortNotesInPlainWords() {
        let prompt = ObserverPrompt.build(previous: nil, earlier: [], lastReply: "Done.", words: 100)
        #expect(ObserverPrompt.maxBullets == 3)
        #expect(prompt.contains("at most 3 bullets"))
        #expect(prompt.contains("plain words"))
        #expect(prompt.contains("no file names"))
        #expect(!prompt.contains("No length limits"))
    }

    @Test func keepsTheFirstThreeBulletsOfAList() {
        let reply = #"{"built":["a","b","c","d","e"],"left":["x"],"just_now":"Hi"}"#
        #expect(ObserverPrompt.parse(reply) == ObserverNotes(built: ["a", "b", "c"], left: ["x"], justNow: "Hi"))
    }

    @Test func rejectsAMalformedReply() {
        #expect(ObserverPrompt.parse("not json") == nil)
        #expect(ObserverPrompt.parse(#"{"built":["a"]}"#) == nil)
        #expect(ObserverPrompt.parse(#"{"built":["a"],"just_now":"  "}"#) == nil)
        #expect(ObserverPrompt.parse(#"{"built":"a","just_now":"b"}"#) == nil)
        #expect(ObserverPrompt.parse("") == nil)
    }
}
#endif
