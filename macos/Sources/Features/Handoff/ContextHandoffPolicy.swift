#if os(macOS)
import Foundation

/// How urgent a pane's handoff is: past the limit (hand off at the next
/// clean break) or at the ceiling (hand off at the end of this turn).
enum ContextHandoffLevel: String, Codable, Equatable {
    case limit, ceiling
}

/// When a conversation is long enough to hand off (spec §2): the user's
/// setting, capped at 70% of the pane's window; the ceiling 100k past it,
/// capped at 90%. The directive is repeated each 25k.
enum ContextHandoffPolicy {
    static let reminderStep = 25_000
    static let ceilingMargin = 100_000

    static func limit(setting: Int, size: Int) -> Int {
        min(setting, size * 70 / 100)
    }

    static func ceiling(setting: Int, size: Int) -> Int {
        min(limit(setting: setting, size: size) + ceilingMargin, size * 90 / 100)
    }

    /// Nil below the limit, or while the window's size is unknown.
    static func level(used: Int, size: Int, setting: Int) -> ContextHandoffLevel? {
        guard size > 0 else { return nil }
        if used >= ceiling(setting: setting, size: size) { return .ceiling }
        if used >= limit(setting: setting, size: size) { return .limit }
        return nil
    }
}
#endif
