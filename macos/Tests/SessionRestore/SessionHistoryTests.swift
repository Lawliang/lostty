#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct SessionHistoryTests {
    let history = SessionHistory(folder: FileManager.default.temporaryDirectory
        .appendingPathComponent("session-history-\(UUID().uuidString)", isDirectory: true))

    /// A tab whose split tree holds `panes`, as `TerminalRestorableState` saves it.
    private func tab(_ panes: [String]) -> Data {
        func node(_ panes: ArraySlice<String>) -> String {
            guard panes.count > 1 else { return #"{"view":{"uuid":"\#(panes.first ?? "")","pwd":"/tmp"}}"# }
            let middle = panes.startIndex + panes.count / 2
            return #"{"split":{"direction":"horizontal","ratio":0.5,"#
                + #""left":\#(node(panes[..<middle])),"right":\#(node(panes[middle...]))}}"#
        }
        return Data(#"{"surfaceTree":{"version":1,"root":\#(node(panes[...]))}}"#.utf8)
    }

    /// A canvas whose cards each hold one list of panes.
    private func canvas(_ cards: [[String]], visible: Bool = false) -> WindowSnapshot.Group {
        let saved = cards.map { panes in
            #"{"frame":[[0,0],[800,600]],"tree":\#(String(decoding: tab(panes), as: UTF8.self))}"#
        }
        let state = #"{"saved":{"visible":\#(visible),"center":[0,0],"zoom":1,"cards":[\#(saved.joined(separator: ","))]}}"#
        return .init(frame: .zero, selected: 0, miniaturized: false, tabs: [],
                     canvas: .init(state: Data(state.utf8), fullscreen: false))
    }

    private func session(_ groups: [WindowSnapshot.Group], claude: [String: String] = [:], at: Double = 0) -> LastSession {
        let windows = WindowSnapshot(groups: groups)
        return LastSession(
            at: Date(timeIntervalSince1970: 2_000_000_000 + at), windows: windows, panes: windows.paneIDs,
            conversations: claude.mapValues { PaneConversation(agent: "claude", id: $0) })
    }

    private func window(_ tabs: [[String]], selected: Int = 0) -> WindowSnapshot.Group {
        .init(frame: .zero, selected: selected, miniaturized: false, tabs: tabs.map(tab))
    }

    @Test func eachChangeInPanesIsANewSnapshotNewestFirst() throws {
        try history.record(session([window([["A"]])], at: 0))
        try history.record(session([window([["A", "B"]])], at: 1))
        try history.record(session([window([["B"]])], at: 2))
        #expect(history.entries().map { Set($0.session.panes) } == [["B"], ["A", "B"], ["A"]])
    }

    @Test func movingWindowsUpdatesTheNewestSnapshot() throws {
        try history.record(session([window([["A"]])], at: 0))
        var moved = session([window([["A"]])], at: 5)
        moved.windows.groups[0].frame = CGRect(x: 10, y: 10, width: 500, height: 400)
        try history.record(moved)
        let entries = history.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.session == moved)
    }

    @Test func aNewConversationIsANewSnapshot() throws {
        try history.record(session([window([["A"]])], at: 0))
        try history.record(session([window([["A"]])], claude: ["A": UUID().uuidString], at: 1))
        #expect(history.entries().count == 2)
    }

    @Test func keepsOnlyTheNewest() throws {
        for n in 0..<(SessionHistory.limit + 5) {
            try history.record(session([window([["pane-\(n)"]])], at: Double(n)))
        }
        let entries = history.entries()
        #expect(entries.count == SessionHistory.limit)
        #expect(entries.first?.session.panes == ["pane-\(SessionHistory.limit + 4)"])
        #expect(entries.last?.session.panes == ["pane-5"])
    }

    @Test func snapshotsInTheSameMillisecondKeepTheirOrder() throws {
        try history.record(session([window([["A"]])]))
        try history.record(session([window([["B"]])]))
        #expect(history.entries().map(\.session.panes) == [["B"], ["A"]])
    }

    @Test func findsEveryPaneInTabsAndCards() {
        let windows = WindowSnapshot(groups: [window([["A", "B", "C"], ["D"]]), canvas([["E"], ["F", "G"]])])
        #expect(Set(windows.paneIDs) == ["A", "B", "C", "D", "E", "F", "G"])
    }

    @Test func reopeningLeavesOutTabsAndCardsWithAPaneOpenNow() throws {
        let saved = session([window([["A", "B"], ["C"]], selected: 1), canvas([["D"], ["E", "F"]])],
                            claude: ["B": "conv-b", "C": "conv-c", "F": "conv-f"])
        let reopened = try #require(saved.reopenable(openPanes: ["A", "E"], openConversations: []))
        #expect(Set(reopened.panes) == ["C", "D"])
        #expect(reopened.conversations == ["C": PaneConversation(agent: "claude", id: "conv-c")])
        #expect(reopened.windows.groups[0].tabs.count == 1)
        #expect(reopened.windows.groups[0].selected == 0)
        // The canvas comes back shown, with only the card that's closed.
        let state = try #require(reopened.windows.groups[1].canvas?.state)
        let root = try #require(try JSONSerialization.jsonObject(with: state) as? [String: Any])
        let canvasSaved = try #require(root["saved"] as? [String: Any])
        #expect(canvasSaved["visible"] as? Bool == true)
        #expect((canvasSaved["cards"] as? [Any])?.count == 1)
    }

    @Test func aConversationRunningElsewhereIsNotResumedTwice() throws {
        let saved = session([window([["A"]])], claude: ["A": "conv-a"])
        let reopened = try #require(saved.reopenable(openPanes: [], openConversations: ["conv-a"]))
        #expect(reopened.panes == ["A"])
        #expect(reopened.conversations.isEmpty)
    }

    @Test func nothingToReopenWhenEverythingIsOpen() {
        let saved = session([window([["A"]]), canvas([["B"]])])
        #expect(saved.reopenable(openPanes: ["A", "B"], openConversations: []) == nil)
    }

    @Test func theCanvasDecodesAfterLeavingOutCards() throws {
        let saved = session([canvas([["D"], ["E"]])])
        let reopened = try #require(saved.reopenable(openPanes: ["E"], openConversations: []))
        let state = try #require(reopened.windows.groups.first?.canvas?.state)
        // Still a CanvasRestorableState's shape (decoded without making panes).
        let decoded = try JSONDecoder().decode(SavedCanvas.self, from: state).saved
        #expect(decoded.cards.count == 1)
        #expect(decoded.visible)
    }
}

/// `CanvasRestorableState`'s JSON, its split trees left undecoded.
private struct SavedCanvas: Codable {
    struct AnyTree: Codable {}
    var saved: CanvasSaved<AnyTree>
}
#endif
