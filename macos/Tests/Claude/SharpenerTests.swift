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

    @Test func readsTheLogsTailWhenTheCutSplitsACharacter() {
        let line = #"{"verdict":"rewritten","original":"é","sent":"b","id":"cc","time":1}"#
        let whole = Data(("xé\n" + line + "\n").utf8)
        // Cut inside the "é" of the first line, as a seek from the end can.
        let tail = whole.subdata(in: 2..<whole.count)
        #expect(Sharpener.entry(id: "cc", in: Sharpener.tailText(tail, cut: true) ?? "")?.original == "é")
    }

    @Test func copiesTheModOutOfTheAppReplacingAnOldCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("bundle/lostty-sharpener")
        let target = root.appendingPathComponent("support/mods/lostty-sharpener")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("hooks"), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: source.appendingPathComponent("hooks/register.ts"))
        try FileManager.default.createDirectory(at: target.appendingPathComponent("hooks"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("hooks/register.ts"))
        try Data("stale".utf8).write(to: target.appendingPathComponent("hooks/gone.ts"))

        #expect(Sharpener.copyMod(from: source, to: target))
        #expect(try String(contentsOf: target.appendingPathComponent("hooks/register.ts"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("hooks/gone.ts").path))
    }

    @MainActor @Test func eachTerminalHasItsOwnSwitchOffByDefault() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = UUID(), two = UUID()
        let sharpens = PaneSharpens(folder: folder)
        #expect(!sharpens.isOn(one))

        sharpens.setOn(true, for: one)
        #expect(sharpens.isOn(one))
        #expect(!sharpens.isOn(two))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("on/\(one.uuidString)").path))
        // A new launch reads the switches back.
        #expect(PaneSharpens(folder: folder).isOn(one))

        sharpens.setOn(false, for: one)
        #expect(!sharpens.isOn(one))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("on/\(one.uuidString)").path))
    }

    @Test func aSharpenedMessageWithNoIDClearsTheStrip() {
        #expect(ClaudeMessage.sharpenCleared(#"{"v":1,"state":"sharpened"}"#))
        #expect(!ClaudeMessage.sharpenCleared(#"{"v":1,"state":"sharpened","id":"a1"}"#))
        #expect(!ClaudeMessage.sharpenCleared(#"{"v":1,"state":"busy"}"#))
    }

    @MainActor @Test func theStripShowsTheLatestRewriteUntilCleared() {
        let sharpens = PaneSharpens(folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let pane = UUID()
        let entry = Sharpener.Entry(id: "bb", original: "a", sent: "b", fixed: nil)
        sharpens.show(entry, on: pane)
        #expect(sharpens.entries[pane] == entry)
        sharpens.clear(pane)
        #expect(sharpens.entries[pane] == nil)
    }
}
#endif
