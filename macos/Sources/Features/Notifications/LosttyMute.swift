#if os(macOS)
import Foundation
import Combine

/// App-wide mute for the terminal's sounds: the bell (system beep or
/// `bell-audio-path`) and the sound of desktop notifications, such as
/// "Command Finished". Toggled from the usage bar; remembered.
@MainActor
final class LosttyMute: ObservableObject {
    static let shared = LosttyMute()
    static let key = "LosttyMuted"

    @Published var isMuted: Bool {
        didSet { defaults.set(isMuted, forKey: Self.key) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMuted = defaults.bool(forKey: Self.key)
    }

    /// For callers off the main actor (notification delegate callbacks).
    nonisolated static func isMuted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}
#endif
