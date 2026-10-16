#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct GuardHookWatchTests {
    @Test func flagsOnlyAgentsThatLostTheirHooks() {
        let before: [HookAgent: ClaudeHooksStatus] = [.claude: .installed, .codex: .installed]
        let after: [HookAgent: ClaudeHooksStatus] = [.claude: .partial, .codex: .installed]
        #expect(GuardHealth.newlyDisconnected(previous: before, current: after) == [.claude])
        #expect(GuardHealth.disconnected(after) == [.claude])
    }

    @Test func neverInstalledIsDisconnectedButNotNewlySo() {
        let before: [HookAgent: ClaudeHooksStatus] = [.codex: .notInstalled]
        let after: [HookAgent: ClaudeHooksStatus] = [.codex: .notInstalled]
        #expect(GuardHealth.newlyDisconnected(previous: before, current: after).isEmpty)
        #expect(GuardHealth.disconnected(after) == [.codex])
    }

    @Test func reconnectingClearsIt() {
        let after: [HookAgent: ClaudeHooksStatus] = [.claude: .installed]
        #expect(GuardHealth.disconnected(after).isEmpty)
    }
}
#endif
