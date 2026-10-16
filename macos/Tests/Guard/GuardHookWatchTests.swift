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

    @Test func aFailedCheckKeepsThePreviousStatus() {
        let before: [HookAgent: ClaudeHooksStatus] = [.claude: .installed]
        let merged = GuardHealth.merge(previous: before, fresh: [.claude: nil])
        #expect(merged == [.claude: .installed])
        #expect(GuardHealth.newlyDisconnected(previous: before, current: merged).isEmpty)
    }

    @Test func aRealUnreadableIsADisconnect() {
        let before: [HookAgent: ClaudeHooksStatus] = [.claude: .installed]
        let merged = GuardHealth.merge(previous: before, fresh: [.claude: .unreadable])
        #expect(GuardHealth.disconnected(merged) == [.claude])
        #expect(GuardHealth.newlyDisconnected(previous: before, current: merged) == [.claude])
    }

    @Test func aFailedCheckWithNoHistoryIsOmitted() {
        #expect(GuardHealth.merge(previous: [:], fresh: [.codex: nil]).isEmpty)
    }
}
#endif
