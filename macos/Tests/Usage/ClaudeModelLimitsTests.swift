#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ClaudeModelLimitsTests {
    @Test func readsEachModelsWeekFromUsage() {
        let text = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 12% used · resets 4pm
        Current week (all models): 41% used · resets Nov 12 at 7:59pm (America/Los_Angeles)
        Current week (Sonnet only): 7% used
        Current week (Fable): 0% used · resets Nov 12 at 8pm (America/Los_Angeles)
        """
        #expect(ClaudeModelLimits.parse(text) == [
            .init(name: "Sonnet", percent: 7, reset: nil),
            .init(name: "Fable", percent: 0, reset: "resets Nov 12 at 8pm (America/Los_Angeles)"),
        ])
    }

    @Test func readsTheAnswersText() {
        let answer = Data(#"{"type":"result","result":"Current week (Fable): 3% used"}"#.utf8)
        #expect(ClaudeModelLimits.text(ofAnswer: answer) == "Current week (Fable): 3% used")
        #expect(ClaudeModelLimits.text(ofAnswer: Data("nope".utf8)) == nil)
    }
}
#endif
