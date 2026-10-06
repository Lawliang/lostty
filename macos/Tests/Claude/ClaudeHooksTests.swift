#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct ClaudeHooksTests {
    @Test func promptsOnlyForClaudeUsersWithMissingOrOldHooks() {
        #expect(ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .notInstalled, promptedVersion: 0))
        #expect(ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .partial, promptedVersion: 0))
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: false, status: .notInstalled, promptedVersion: 0))
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .installed, promptedVersion: 0))
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .unreadable, promptedVersion: 0))
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: nil, promptedVersion: 0))
    }

    @Test func answeredPromptIsNotRepeatedForTheSameVersion() {
        let v = ClaudeHooksPrompt.hookVersion
        #expect(!ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .notInstalled, promptedVersion: v))
        #expect(ClaudeHooksPrompt.shouldPrompt(claudeDirExists: true, status: .partial, promptedVersion: v - 1))
    }

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

    @Test func runReportsAMissingBinary() {
        let cli = ClaudeHooksCLI(binary: URL(fileURLWithPath: "/nonexistent/ghostty"))
        let result = cli.run("status")
        #expect(result.exitCode != 0)
        #expect(cli.status() == nil)
    }
}
#endif
