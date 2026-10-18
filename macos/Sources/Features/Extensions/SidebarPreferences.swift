#if os(macOS)
import Foundation

/// Lostty Settings → Sidebar. Every window observes it, so a change applies
/// everywhere at once.
@MainActor
final class SidebarPreferences: ObservableObject {
    static let shared = SidebarPreferences()
    static let autoHideKey = "LosttySidebarAutoHide"

    private let defaults: UserDefaults

    /// Hide the icon strip until the pointer reaches the window's right
    /// edge. It never hides while an app is open.
    @Published var autoHide: Bool {
        didSet { defaults.set(autoHide, forKey: Self.autoHideKey) }
    }

    init(defaults: UserDefaults = .ghostty) {
        self.defaults = defaults
        autoHide = defaults.bool(forKey: Self.autoHideKey)
    }
}
#endif
