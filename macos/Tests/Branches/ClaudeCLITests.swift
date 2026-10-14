#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ClaudeCLITests {
    @Test func locateTakesTheLastAbsolutePath() {
        #expect(ClaudeCLI.parseLocate("welcome to zsh\n/Users/me/.local/bin/claude\n") == "/Users/me/.local/bin/claude")
        #expect(ClaudeCLI.parseLocate("claude: aliased to foo\n") == nil)
        #expect(ClaudeCLI.parseLocate("") == nil)
    }

    @Test func runsHeadlessWithNoToolsOnHaiku() {
        let args = ClaudeCLI.arguments
        #expect(args.first == "-p")
        #expect(args.contains("--no-session-persistence"))
        #expect(args.firstIndex(of: "--model").map { args[$0 + 1] } == "haiku")
        #expect(args.firstIndex(of: "--tools").map { args[$0 + 1] } == "")
    }

    @Test func successIsTheTrimmedText() {
        let result = ProcessResult(status: 0, stdout: "  Adds X.\n", stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .success("Adds X."))
    }

    @Test func failureShowsTheFirstErrorLine() {
        let result = ProcessResult(status: 1, stdout: "", stderr: "\nInvalid API key · Please run /login\nmore\n")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Invalid API key · Please run /login")))
    }

    @Test func failureWithNoOutputNamesTheStatus() {
        let result = ProcessResult(status: 2, stdout: "", stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Claude exited with status 2")))
    }

    @Test func emptyOutputIsAFailure() {
        let result = ProcessResult(status: 0, stdout: "\n", stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Claude returned nothing")))
    }

    @Test func noResultIsATimeoutAndCancelWins() {
        #expect(ClaudeCLI.interpret(nil, cancelled: false) == .failure(.timedOut))
        #expect(ClaudeCLI.interpret(ProcessResult(status: 9, stdout: "", stderr: ""), cancelled: true) == .failure(.cancelled))
    }

    @Test func errorsHaveReadableMessages() {
        #expect(SummaryError.timedOut.message == "Claude took longer than a minute.")
        #expect(SummaryError.git.message == "Couldn't read this branch's changes.")
        #expect(SummaryError.failed("x").message == "x")
    }

    @Test func locatesOtherCommandsToo() {
        #expect(ClaudeCLI.locate(command: "sh", shell: "/bin/sh") == "/bin/sh")
    }

    @Test func asksForJSONSoRunsReportTheirTokens() {
        let args = ClaudeCLI.arguments
        #expect(args.firstIndex(of: "--output-format").map { args[$0 + 1] } == "json")
    }

    /// Trimmed from a real `claude -p --output-format json` run on Haiku.
    static let jsonRun = #"""
    {"type":"result","subtype":"success","is_error":false,"result":"  Adds X.\n","session_id":"s",
     "total_cost_usd":0.0006,"usage":{"input_tokens":2,"output_tokens":4},
     "modelUsage":{"claude-haiku-5-5":{"inputTokens":2,"outputTokens":4,"cacheReadInputTokens":649,
       "cacheCreationInputTokens":2995,"costUSD":0.0006}}}
    """#

    @Test func jsonOutputGivesTheTextAndTheTokens() {
        let result = ProcessResult(status: 0, stdout: Self.jsonRun, stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .success("Adds X."))
        #expect(ClaudeCLI.usage(result)
            == ["claude-haiku-5-5": TokenCounts(input: 2, output: 4, cacheWrite: 2995, cacheRead: 649)])
    }

    @Test func aJSONErrorShowsItsTextAndStillCountsItsTokens() {
        let json = #"{"type":"result","is_error":true,"result":"Prompt is too long","#
            + #""modelUsage":{"claude-haiku-5-5":{"inputTokens":9,"outputTokens":0}}}"#
        let result = ProcessResult(status: 1, stdout: json, stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Prompt is too long")))
        #expect(ClaudeCLI.usage(result) == ["claude-haiku-5-5": TokenCounts(input: 9)])
    }

    @Test func aJSONErrorWithNoTextNamesTheStatus() {
        let result = ProcessResult(status: 3, stdout: #"{"type":"result","is_error":true,"modelUsage":{}}"#, stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Claude exited with status 3")))
        #expect(ClaudeCLI.usage(result) == nil)
    }

    @Test func anEmptyJSONResultIsAFailure() {
        let result = ProcessResult(status: 0, stdout: #"{"type":"result","is_error":false,"result":"  "}"#, stderr: "")
        #expect(ClaudeCLI.interpret(result, cancelled: false) == .failure(.failed("Claude returned nothing")))
    }

    @Test func plainOrBrokenOutputWorksAsBeforeWithNoTokens() {
        #expect(ClaudeCLI.usage(ProcessResult(status: 0, stdout: "Adds X.\n", stderr: "")) == nil)
        let broken = ProcessResult(status: 0, stdout: #"{"type":"res"#, stderr: "")
        #expect(ClaudeCLI.usage(broken) == nil)
        #expect(ClaudeCLI.interpret(broken, cancelled: false) == .success(#"{"type":"res"#))
        #expect(ClaudeCLI.usage(nil) == nil)
        // Another JSON object (the observer's notes, printed by a stand-in) is plain text.
        let notes = ProcessResult(status: 0, stdout: #"{"built":[],"just_now":"hi"}"#, stderr: "")
        #expect(ClaudeCLI.interpret(notes, cancelled: false) == .success(#"{"built":[],"just_now":"hi"}"#))
        #expect(ClaudeCLI.usage(notes) == nil)
    }
}
#endif
