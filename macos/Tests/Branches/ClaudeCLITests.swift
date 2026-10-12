#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

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
}
#endif
