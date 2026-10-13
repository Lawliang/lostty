import Foundation
import Testing
@testable import LosttyRemote

struct AttachPreambleTests {
    func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    @Test func theLoginBannerAndEchoedCommandNeverShow() {
        var preamble = AttachPreamble()
        #expect(preamble.feed(Data("Last login: Mon Oct 12 from 100.126.63.10\r\n".utf8)).isEmpty)
        #expect(preamble.feed(Data(" [ \"$(PATH=... tmux display-message ...)\" = 'lostty' ] || exit 1; exec env ...\r\n".utf8)).isEmpty)
        let shown = preamble.feed(Data("\u{1b}[?1049h\u{1b}[H\u{1b}[2Jtmux screen".utf8))
        #expect(text(shown) == "\u{1b}[?1049h\u{1b}[H\u{1b}[2Jtmux screen")
        #expect(preamble.passing)
        // From then on, everything passes.
        #expect(text(preamble.feed(Data("more".utf8))) == "more")
    }

    @Test func theTakeoverSplitAcrossReadsIsStillFound() {
        var preamble = AttachPreamble()
        #expect(preamble.feed(Data("banner\u{1b}[?10".utf8)).isEmpty)
        #expect(text(preamble.feed(Data("49hscreen".utf8))) == "\u{1b}[?1049hscreen")
    }

    @Test func anAttachThatFailsShowsWhatItSaid() {
        var preamble = AttachPreamble()
        _ = preamble.feed(Data("zsh: command not found: tmux\r\n".utf8))
        #expect(text(preamble.flush()) == "zsh: command not found: tmux\r\n")
        #expect(preamble.flush().isEmpty)
    }

    @Test func tooMuchBeforeTmuxIsShownNotHeld() {
        var preamble = AttachPreamble()
        let big = Data(repeating: UInt8(ascii: "x"), count: AttachPreamble.limit + 1)
        #expect(preamble.feed(big).count == big.count)
        #expect(preamble.passing)
    }
}
