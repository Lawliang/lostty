#if os(macOS)
import Combine
import Foundation

/// Lostty Settings → Notifications. `style`: how a terminal that finished
/// while you weren't looking asks for you. Muted, Lostty shows no bubbles at the
/// top right and no Mac banners, apart from an agent asking for approval.
/// While muted a marker file exists, so a sound hook can stay quiet too:
/// `[ -e "$HOME/Library/Application Support/Lostty/notifications-muted" ] || afplay …`.
@MainActor
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()
    nonisolated static let mutedKey = "LosttyNotificationsMuted"
    nonisolated static let styleKey = "LosttyNotificationStyle"

    enum Style: String, CaseIterable {
        /// A bubble at the top right.
        case bubbles
        /// On the canvas, an avatar and an arrow at the edge toward its card.
        case arrows

        var title: String {
            switch self {
            case .bubbles: "Bubbles"
            case .arrows: "Arrows"
            }
        }
    }

    /// The saved setting, from any thread.
    nonisolated static var isMuted: Bool { UserDefaults.ghostty.bool(forKey: mutedKey) }

    nonisolated static var defaultMarker: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lostty/notifications-muted")
    }

    private let defaults: UserDefaults
    private let marker: URL?

    @Published var muted: Bool {
        didSet {
            defaults.set(muted, forKey: Self.mutedKey)
            writeMarker()
            if muted { onMute() }
        }
    }

    @Published var style: Style {
        didSet {
            defaults.set(style.rawValue, forKey: Self.styleKey)
            if style == .arrows { TerminalNotices.shared.clear() }
        }
    }

    /// Whether a finished terminal posts a bubble.
    var showsTerminalBubbles: Bool { !muted && style == .bubbles }

    /// Whether the canvas points at finished terminals.
    var showsArrows: Bool { !muted && style == .arrows }

    /// Clears what's showing when the owner mutes.
    var onMute: @MainActor () -> Void = {
        LosttyNotifications.shared.clear()
        TerminalNotices.shared.clear()
    }

    init(defaults: UserDefaults = .ghostty, marker: URL? = NotificationPreferences.defaultMarker) {
        self.defaults = defaults
        self.marker = marker
        muted = defaults.bool(forKey: Self.mutedKey)
        style = defaults.string(forKey: Self.styleKey).flatMap(Style.init(rawValue:)) ?? .arrows
    }

    private func writeMarker() {
        guard let marker else { return }
        if muted {
            try? FileManager.default.createDirectory(
                at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        } else {
            try? FileManager.default.removeItem(at: marker)
        }
    }
}
#endif
