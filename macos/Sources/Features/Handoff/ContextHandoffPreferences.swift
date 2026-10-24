#if os(macOS)
import Foundation

/// Lostty Settings → Handoff: whether long conversations hand off, and
/// after how many tokens (spec §2).
@MainActor
final class ContextHandoffPreferences: ObservableObject {
    static let shared = ContextHandoffPreferences()
    static let enabledKey = "LosttyHandoffEnabled"
    static let limitKey = "LosttyHandoffLimit"
    /// Debug builds only: a limit in tokens for desk checks (20000).
    static let overrideKey = "LosttyHandoffLimitOverride"
    static let limits = [200_000, 300_000, 400_000, 500_000, 600_000]
    static let defaultLimit = 300_000

    private let defaults: UserDefaults

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }

    @Published var limit: Int {
        didSet { defaults.set(limit, forKey: Self.limitKey) }
    }

    init(defaults: UserDefaults = .ghostty) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
        let saved = defaults.integer(forKey: Self.limitKey)
        limit = Self.limits.contains(saved) ? saved : Self.defaultLimit
    }

    /// The limit the policy uses: the Debug override, else the setting.
    var setting: Int {
        #if DEBUG
        let override = defaults.integer(forKey: Self.overrideKey)
        if override > 0 { return override }
        #endif
        return limit
    }
}
#endif
