#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct UsageBreakdownTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let hour: TimeInterval = 3600

    func use(_ part: UsagePart, _ weight: Double, hoursAgo: Double = 1) -> WeightedUse {
        WeightedUse(at: now - hoursAgo * hour, part: part, weight: weight)
    }

    @Test func thePartsSplitThePercentageByWeight() throws {
        let limit = ClaudeUsageReport.Limit(percent: 42, resetsAt: now + 2 * hour)
        let split = try #require(UsageBreakdown.make(
            limit: limit, length: UsageBreakdown.session,
            uses: [use(.claudeCode, 900), use(.lostty, 100), use(.claudeCode, 50)], now: now))
        #expect(abs(split.claudeCode + split.lostty - 42) < 1e-9)
        #expect(abs(split.lostty - 42 * 100 / 1050) < 1e-9)
    }

    @Test func theWindowEndsAtTheReset() throws {
        // Session resets in 2 h, so it began 3 h ago: older uses don't count.
        let limit = ClaudeUsageReport.Limit(percent: 10, resetsAt: now + 2 * hour)
        let split = try #require(UsageBreakdown.make(
            limit: limit, length: UsageBreakdown.session,
            uses: [use(.claudeCode, 100, hoursAgo: 2), use(.lostty, 100, hoursAgo: 4)], now: now))
        #expect(split == UsageBreakdown(claudeCode: 10, lostty: 0))
    }

    @Test func withoutAResetTimeTheWindowEndsNow() throws {
        let limit = ClaudeUsageReport.Limit(percent: 10, resetsAt: nil)
        let split = try #require(UsageBreakdown.make(
            limit: limit, length: UsageBreakdown.session,
            uses: [use(.lostty, 100, hoursAgo: 4), use(.claudeCode, 100, hoursAgo: 6)], now: now))
        #expect(split == UsageBreakdown(claudeCode: 0, lostty: 10))
    }

    @Test func noLimitOrAResetLimitHasNoBreakdown() {
        let uses = [use(.claudeCode, 100)]
        #expect(UsageBreakdown.make(limit: nil, length: UsageBreakdown.session, uses: uses, now: now) == nil)
        let reset = ClaudeUsageReport.Limit(percent: 42, resetsAt: now - 60)
        #expect(UsageBreakdown.make(limit: reset, length: UsageBreakdown.session, uses: uses, now: now) == nil)
        let zero = ClaudeUsageReport.Limit(percent: 0.4, resetsAt: now + hour)
        #expect(UsageBreakdown.make(limit: zero, length: UsageBreakdown.session, uses: uses, now: now) == nil)
    }

    @Test func nothingCountedHasNoBreakdown() {
        let limit = ClaudeUsageReport.Limit(percent: 42, resetsAt: now + hour)
        #expect(UsageBreakdown.make(limit: limit, length: UsageBreakdown.session, uses: [], now: now) == nil)
        #expect(UsageBreakdown.make(limit: limit, length: UsageBreakdown.session,
                                    uses: [use(.claudeCode, 100, hoursAgo: 30)], now: now) == nil)
    }

    @Test func theTextAddsUpToTheShownPercentage() {
        #expect(UsageBreakdown(claudeCode: 40.6, lostty: 1.4).text == "Claude Code ≈ 41 · Lostty ≈ 1")
        #expect(UsageBreakdown(claudeCode: 41.4, lostty: 0.4).text == "Claude Code ≈ 42 · Lostty <1")
        #expect(UsageBreakdown(claudeCode: 0.3, lostty: 9.7).text == "Claude Code <1 · Lostty ≈ 10")
        #expect(UsageBreakdown(claudeCode: 17, lostty: 0).text == "Claude Code ≈ 17 · Lostty ≈ 0")
        #expect(UsageBreakdown(claudeCode: 40.5, lostty: 0.5).text == "Claude Code ≈ 40 · Lostty ≈ 1")
    }
}
#endif
