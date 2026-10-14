#if os(macOS)
import Combine
import Foundation

/// The usage popover's breakdown: counts when the popover opens (reusing a
/// count for a minute), and words each limit's line.
@MainActor
final class UsageBreakdownRuntime: ObservableObject {
    static let shared = UsageBreakdownRuntime()
    static let reuse: TimeInterval = 60
    static let counting = "Counting…"
    static let footnote = "Estimated from Claude use in Lostty."

    /// Everything counted in the last week; nil before the first count.
    @Published private(set) var uses: [WeightedUse]?
    @Published private(set) var isCounting = false

    private let ledger: UsageLedger
    private let counter: UsageCounter
    private let now: () -> Date
    private var countedAt: Date?

    init(ledger: UsageLedger = .shared, counter: UsageCounter = UsageCounter(), now: @escaping () -> Date = Date.init) {
        self.ledger = ledger
        self.counter = counter
        self.now = now
    }

    /// Counts again, unless a count is under way or under a minute old
    /// (then nil). The count runs on the counter actor, off the main thread.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        let now = self.now()
        guard !isCounting else { return nil }
        if let countedAt, now.timeIntervalSince(countedAt) < Self.reuse { return nil }
        isCounting = true
        let since = now - UsageBreakdown.week
        let conversations = ledger.conversations(now: now)
        let runs = ledger.runs(now: now)
        let counter = counter
        return Task {
            let code = await counter.count(conversations, since: since)
            self.uses = code + UsageCounter.uses(of: runs, since: since)
            self.countedAt = now
            self.isCounting = false
        }
    }

    func breakdown(_ metric: ClaudeUsageMetric, usage: ClaudeUsageRuntime) -> UsageBreakdown? {
        guard let uses else { return nil }
        switch metric {
        case .session:
            return UsageBreakdown.make(limit: usage.fiveHour, length: UsageBreakdown.session, uses: uses, now: now())
        case .weekly:
            return UsageBreakdown.make(limit: usage.sevenDay, length: UsageBreakdown.week, uses: uses, now: now())
        case .weeklyFable:
            return nil
        }
    }

    /// The row's breakdown line: the split, "Counting…" during the first
    /// count, or nil (no limit report, nothing counted, Weekly · Fable).
    func line(_ metric: ClaudeUsageMetric, usage: ClaudeUsageRuntime) -> String? {
        if uses == nil {
            return isCounting && metric != .weeklyFable && usage.percent(metric) != nil ? Self.counting : nil
        }
        return breakdown(metric, usage: usage)?.text
    }
}
#endif
