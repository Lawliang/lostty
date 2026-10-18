#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct ClaudeHooksTests {
    @Test func parsesStatusOutput() {
        #expect(ClaudeHooksStatus(cliOutput: "installed\n") == .installed)
        #expect(ClaudeHooksStatus(cliOutput: "not-installed\n") == .notInstalled)
        #expect(ClaudeHooksStatus(cliOutput: "partial") == .partial)
        #expect(ClaudeHooksStatus(cliOutput: "unreadable\n") == .unreadable)
        #expect(ClaudeHooksStatus(cliOutput: "") == nil)
    }

    @Test func successSaysToRestartClaude() {
        // Claude reads hooks at session start, so a running session sees no change.
        #expect(ClaudeHooksPrompt.successMessage(for: "install")?.contains("Restart") == true)
        #expect(ClaudeHooksPrompt.successMessage(for: "remove")?.contains("Restart") == true)
        #expect(ClaudeHooksPrompt.successMessage(for: "status") == nil)
    }

    @Test func onlyCoordinationOnMentionsTheGuard() {
        #expect(ClaudeHooksPrompt.successMessage(for: "install", coordination: false)?.contains("guard") == false)
        #expect(ClaudeHooksPrompt.successMessage(for: "install", coordination: true)?.contains("guard") == true)
    }

    @Test func runReportsAMissingBinary() {
        let cli = ClaudeHooksCLI(binary: URL(fileURLWithPath: "/nonexistent/ghostty"))
        let result = cli.run("status")
        #expect(result.exitCode != 0)
        #expect(cli.status() == nil)
    }
}
#endif
