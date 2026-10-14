#if os(macOS)
import Foundation

/// One limit's percentage split between Claude Code and Lostty by weighted
/// tokens (usage breakdown spec §1), in percentage points. An estimate:
/// use Lostty can't see is folded into the two parts.
struct UsageBreakdown: Equatable {
    var claudeCode: Double
    var lostty: Double

    static let session: TimeInterval = 5 * 3600
    static let week: TimeInterval = 7 * 24 * 3600

    /// The split of `limit` over its window, `[resetsAt − length, now]`
    /// (`now − length` without a reset time). Nil without a limit, while it
    /// shows 0% (or has reset), and with nothing counted in the window.
    static func make(
        limit: ClaudeUsageReport.Limit?, length: TimeInterval, uses: [WeightedUse], now: Date
    ) -> UsageBreakdown? {
        guard let limit else { return nil }
        let percent = limit.percent(at: now)
        guard Int(percent.rounded()) > 0 else { return nil }
        let start = (limit.resetsAt ?? now) - length
        var code = 0.0
        var lostty = 0.0
        for use in uses where use.at >= start && use.at <= now {
            switch use.part {
            case .claudeCode: code += use.weight
            case .lostty: lostty += use.weight
            }
        }
        let total = code + lostty
        guard total > 0 else { return nil }
        return UsageBreakdown(claudeCode: percent * code / total, lostty: percent * lostty / total)
    }

    /// "Claude Code ≈ 41 · Lostty ≈ 1": whole points that add up to the
    /// percentage the row shows; a part under half a point is "<1".
    var text: String {
        let total = Int((claudeCode + lostty).rounded())
        let lostty = min(Int(self.lostty.rounded()), total)
        let code = total - lostty
        func part(_ name: String, _ points: Double, _ whole: Int) -> String {
            points > 0 && points < 0.5 ? "\(name) <1" : "\(name) ≈ \(whole)"
        }
        return part("Claude Code", claudeCode, code) + " · " + part("Lostty", self.lostty, lostty)
    }
}
#endif
