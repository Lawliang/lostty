#if os(macOS)
import Foundation

/// Lostty Settings → Updates. The config's `auto-update`, when set, wins
/// (UpdateFeed.schedule).
@MainActor
final class UpdatePreferences: ObservableObject {
    static let shared = UpdatePreferences()
    static let installsAutomaticallyKey = "LosttyInstallUpdatesAutomatically"

    private let defaults: UserDefaults

    /// Download updates in the background, ready for Restart to Update. Off,
    /// Lostty asks before downloading one. On unless turned off.
    @Published var installsAutomatically: Bool {
        didSet { defaults.set(installsAutomatically, forKey: Self.installsAutomaticallyKey) }
    }

    init(defaults: UserDefaults = .ghostty) {
        self.defaults = defaults
        installsAutomatically = Self.installsAutomatically(in: defaults)
    }

    /// The setting, read from any thread (a config reload).
    nonisolated static func installsAutomatically(in defaults: UserDefaults = .ghostty) -> Bool {
        defaults.object(forKey: installsAutomaticallyKey) as? Bool ?? true
    }
}
#endif
