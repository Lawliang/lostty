#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct SharpenerTests {
    @Test func addsTheModToThePanesPluginFolders() {
        #expect(Sharpener.pluginDirs(existing: nil, mod: "/A/mod") == "/A/mod")
        #expect(Sharpener.pluginDirs(existing: "", mod: "/A/mod") == "/A/mod")
        #expect(Sharpener.pluginDirs(existing: "/mine", mod: "/A/mod") == "/mine:/A/mod")
        #expect(Sharpener.pluginDirs(existing: "/mine:/A/mod", mod: "/A/mod") == "/mine:/A/mod")
    }

    @Test func readsTheSharpenedMessagesID() {
        // Exact JSON `+sharpen-log` encodes (see sharpen_log.zig).
        #expect(ClaudeMessage.sharpened(#"{"v":1,"state":"sharpened","id":"a1b2c3"}"#) == "a1b2c3")
        #expect(ClaudeMessage.sharpened(#"{"v":1,"state":"busy"}"#) == nil)
        #expect(ClaudeMessage.sharpened(#"{"v":1,"state":"sharpened","id":"../x"}"#) == nil)
        #expect(ClaudeMessage.sharpened(#"{"v":2,"state":"sharpened","id":"a1"}"#) == nil)
    }

    @Test func findsTheEntryInTheLog() {
        let log = """
        {"verdict":"clean","original":"why?","sent":"why?","id":"aa","time":1}
        not json
        {"verdict":"rewritten","original":"the scroll thing","sent":"scrolling broke. repro first.","fixed":["repro first"],"tells":["filler"],"id":"bb","time":2}

        """
        let entry = Sharpener.entry(id: "bb", in: log)
        #expect(entry?.original == "the scroll thing")
        #expect(entry?.sent == "scrolling broke. repro first.")
        #expect(entry?.fixed == ["repro first"])
        #expect(Sharpener.entry(id: "zz", in: log) == nil)
    }

    @Test func aSharpenedMessageWithNoIDClearsTheStrip() {
        #expect(ClaudeMessage.sharpenCleared(#"{"v":1,"state":"sharpened"}"#))
        #expect(!ClaudeMessage.sharpenCleared(#"{"v":1,"state":"sharpened","id":"a1"}"#))
        #expect(!ClaudeMessage.sharpenCleared(#"{"v":1,"state":"busy"}"#))
    }

    @MainActor @Test func theStripShowsTheLatestRewriteUntilCleared() {
        let sharpens = PaneSharpens()
        let pane = UUID()
        let entry = Sharpener.Entry(id: "bb", original: "a", sent: "b", fixed: nil)
        sharpens.show(entry, on: pane)
        #expect(sharpens.entries[pane] == entry)
        sharpens.clear(pane)
        #expect(sharpens.entries[pane] == nil)
    }
}
#endif
