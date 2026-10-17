#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ContextHandoffStoreTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("handoff-\(UUID())")
    var store: ContextHandoffStore { ContextHandoffStore(root: root) }
    let pane = UUID()

    @Test func theHookFilesAreWhereTheZigHookLooks() throws {
        store.writeSay(pane, "say this")
        store.writeStart(pane, "start this")
        let dir = root.appendingPathComponent("handoff/panes")
        #expect(try String(contentsOf: dir.appendingPathComponent("\(pane.uuidString).say"), encoding: .utf8) == "say this")
        #expect(try String(contentsOf: dir.appendingPathComponent("\(pane.uuidString).start"), encoding: .utf8) == "start this")
        store.removeSay(pane)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(pane.uuidString).say").path))
        store.removeAll(pane)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(pane.uuidString).start").path))
    }

    @Test func statesRoundTrip() {
        let state = ContextHandoffPane(phase: .armed, level: .limit, byButton: false, saidAt: 300_000,
                                       used: 310_000, size: 1_000_000)
        store.saveState(pane, state)
        #expect(store.loadStates() == [pane: state])
        store.removeAll(pane)
        #expect(store.loadStates().isEmpty)
    }

    @Test func handoffsAreNamedByProjectAndTimeAndNeverOverwritten() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try store.saveHandoff("one", project: "lostty-beta", at: date)
        let second = try store.saveHandoff("two", project: "lostty-beta", at: date)
        #expect(first.deletingLastPathComponent().lastPathComponent == "lostty-beta")
        #expect(first.pathExtension == "md")
        #expect(first != second)
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
        #expect(try String(contentsOf: second, encoding: .utf8) == "two")
    }

    @Test func aSlashInTheProjectNameCantLeaveTheFolder() throws {
        let url = try store.saveHandoff("x", project: "../evil/name", at: Date())
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().path
                == root.appendingPathComponent("handoffs").path)
    }

    @Test func onlyTheLast50PerProjectAreKept() throws {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<52 {
            _ = try store.saveHandoff("h\(i)", project: "p", at: date)
            date += 60
        }
        let dir = root.appendingPathComponent("handoffs/p")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names.count == 50)
        #expect(try String(contentsOf: dir.appendingPathComponent(names.last!), encoding: .utf8) == "h51")
    }

    @Test func theLastReplyIsReadFromTheFilesEnd() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("t.jsonl")
        let lines = [
            #"{"type":"user","message":{"content":"Build it"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Working."}]}}"#,
            #"{"type":"user","message":{"content":"Now the tests"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Done.\n<lostty-handoff>"}]}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(ContextHandoffReply.last(in: url, agent: .claude) == "Done.\n<lostty-handoff>")
    }
}
#endif
