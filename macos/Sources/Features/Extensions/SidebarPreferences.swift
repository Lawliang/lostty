#if os(macOS)
import Foundation

/// Lostty Settings → Sidebar. Every window observes it, so a change applies
/// everywhere at once.
@MainActor
final class SidebarPreferences: ObservableObject {
    static let shared = SidebarPreferences()
    static let autoHideKey = "LosttySidebarAutoHide"

    private let defaults: UserDefaults

    /// Hide the icon strip until it's opened from the handle on the
    /// window's right edge. It never hides while an app is open. On unless
    /// the person turned it off.
    @Published var autoHide: Bool {
        didSet { defaults.set(autoHide, forKey: Self.autoHideKey) }
    }

    init(defaults: UserDefaults = .ghostty) {
        self.defaults = defaults
        autoHide = defaults.object(forKey: Self.autoHideKey) as? Bool ?? true
    }
}
#endif
