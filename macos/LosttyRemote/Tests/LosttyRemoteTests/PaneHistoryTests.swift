import Foundation
import Testing
@testable import LosttyRemote

struct PaneHistoryTests {
    @Test func theCommandReadsTheSizeTheWheelTestAndTheLines() throws {
        #expect(try PaneHistory.command(sessionID: "$7", lines: 500) ==
            "\(TmuxRemote.tmux) if-shell -F -t '$7' '#{&&:#{pane_in_mode},#{==:#{cursor-colour},#010203}}'"
            + " 'send-keys -X -t '\\''$7'\\'' cancel' \\; display-message -p -t '$7' "
            + "'lostty-history #{pane_width} #{pane_height} #{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}'"
            + " \\; capture-pane -p -e -S -500 -t '$7'")
        #expect(throws: TmuxRemoteError.badSessionID("x; rm")) {
            try PaneHistory.command(sessionID: "x; rm", lines: 5)
        }
    }

    @Test func parsesTheHeaderAndLinesKeepingBlankOnes() throws {
        let output = Data("lostty-history 40 3 0\none\n\u{1B}[31mtwo\n\nfour\n".utf8)
        let history = try #require(PaneHistory.parse(output))
        #expect(history.cols == 40)
        #expect(history.rows == 3)
        #expect(!history.takesWheel)
        #expect(history.lines == ["one", "\u{1B}[31mtwo", "", "four"].map { Data($0.utf8) })
        #expect(history.scrollback == 1)
    }

    @Test func aPaneThatScrollsItselfTakesTheWheel() {
        #expect(PaneHistory.parse(Data("lostty-history 40 3 1\na\n".utf8))?.takesWheel == true)
    }

    @Test func refusesOutputThatIsNotAHistory() {
        #expect(PaneHistory.parse(Data("can't find session: $7\n".utf8)) == nil)
        #expect(PaneHistory.parse(Data("lostty-history 0 3 0\n".utf8)) == nil)
        #expect(PaneHistory.parse(Data()) == nil)
    }

    @Test func theFeedHidesTheCursorAndKeepsColoursAcrossLineBreaks() {
        let history = PaneHistory(cols: 10, rows: 1, lines: ["a", "b"].map { Data($0.utf8) }, takesWheel: false)
        #expect(String(decoding: history.feed, as: UTF8.self)
            == "\u{1B}[?25la\u{1B}7\u{1B}[0m\r\n\u{1B}8\u{1B}[B\rb")
    }

    private func layout(lines: Int = 100) -> HistoryLayout {
        // A 10-line screen with 2pt above it, in blocks of 11.
        HistoryLayout(lineHeight: 20, lines: lines, rows: 10, chunkRows: 11, top: 2, height: 206)
    }

    @Test func atTheBottomTheScreensLinesSitWhereTheLiveTerminalDrawsThem() {
        // Line 90, the screen's first, is block 8's second line.
        #expect(layout().chunkTop(8, offset: 0) == 2 + Double(88 - 90) * 20)
        #expect(layout().visibleChunks(offset: 0) == 8...9)
    }

    @Test func scrollingBackMovesEveryBlockDownByTheSamePoints() {
        let l = layout()
        #expect(l.chunkTop(8, offset: 7) == l.chunkTop(8, offset: 0) + 7)
        #expect(l.visibleChunks(offset: 200) == 7...8)
    }

    @Test func backAsFarAsTheOldestLineAtTheTop() {
        let l = layout()
        #expect(l.maxOffset == 1800)
        #expect(l.clamped(5000) == 1800)
        #expect(l.clamped(-3) == 0)
        #expect(l.chunkTop(0, offset: 1800) == 2)
        #expect(l.visibleChunks(offset: 1800) == 0...0)
        #expect(l.chunkCount == 10)
    }

    @Test func aBlockReplaysTheColoursInEffectWhereItStarts() {
        let history = PaneHistory(cols: 10, rows: 1, lines: [
            "\u{1B}[31ma", "b", "\u{1B}[0mc", "\u{1B}[44md", "\u{1B}[1me", "\u{1B}[0;32mf", "g",
        ].map { Data($0.utf8) }, takesWheel: false)
        #expect(history.carriedStyle(at: 2) == Data("\u{1B}[31m".utf8))
        #expect(history.carriedStyle(at: 3).isEmpty)
        #expect(history.carriedStyle(at: 5) == Data("\u{1B}[44m\u{1B}[1m".utf8))
        #expect(history.carriedStyle(at: 7) == Data("\u{1B}[0;32m".utf8))
    }

    @Test func aBlocksFeedIsItsLinesAfterTheCarriedColours() {
        let history = PaneHistory(cols: 10, rows: 1, lines: ["\u{1B}[31ma", "b", "c"].map { Data($0.utf8) },
                                  takesWheel: false)
        #expect(String(decoding: history.chunkFeed(0, rows: 2), as: UTF8.self)
            == "\u{1B}[?25l\u{1B}[31ma\u{1B}7\u{1B}[0m\r\n\u{1B}8\u{1B}[B\rb")
        #expect(String(decoding: history.chunkFeed(1, rows: 2), as: UTF8.self) == "\u{1B}[?25l\u{1B}[31mc")
        #expect(String(decoding: history.chunkFeed(5, rows: 2), as: UTF8.self) == "\u{1B}[?25l\u{1B}[31m")
    }
}
