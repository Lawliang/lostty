#if os(macOS)
import Foundation

/// Lostty Settings → Turn summaries: whether the observer summarizes each
/// turn as it ends (on) or only when asked (off).
@MainActor
final class ObserverPreferences: ObservableObject {
    static let shared = ObserverPreferences()
    static let backgroundKey = "LosttyObserverBackground"

    private let defaults: UserDefaults

    @Published var background: Bool {
        didSet { defaults.set(background, forKey: Self.backgroundKey) }
    }

    init(defaults: UserDefaults = .ghostty) {
        self.defaults = defaults
        background = defaults.object(forKey: Self.backgroundKey) as? Bool ?? true
    }
}
#endif
