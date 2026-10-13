#if os(macOS)
import Combine
import Foundation
import LosttyRemote

/// Lostty Mobile: writes each of this Lostty's sessions' skin colors into
/// tmux (`@lostty_skin`) whenever a pane's look changes, so the phone draws
/// the session's row in the pane's colors.
@MainActor
final class SkinTmuxSync {
    static let shared = SkinTmuxSync()

    private var watchers: Set<AnyCancellable> = []

    func start() {
        guard watchers.isEmpty else { return }
        let manager = SkinsRuntime.shared.manager
        // Previews change many times a second while dragging a color.
        manager.$panes.combineLatest(manager.$config)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { _ in Self.sync() }
            .store(in: &watchers)
        // A session made after the change, or a write tmux dropped, catches up.
        NotificationCenter.default.publisher(for: .losttySessionsChanged)
            .sink { _ in MainActor.assumeIsolated { Self.sync() } }
            .store(in: &watchers)
    }

    private static func sync() {
        TmuxOptionSync.sync(option: TmuxRemote.skinOption, desired: desired(), current: { $0.skin?.encoded })
    }

    /// Pane (uuidString) → its skin, encoded; panes without one are left out.
    private static func desired() -> [String: String] {
        let manager = SkinsRuntime.shared.manager
        var result: [String: String] = [:]
        for id in manager.panes.keys {
            guard let skin = manager.effectiveSkin(id) else { continue }
            // A logo's tile is a file here, which the phone fetches.
            var logoTile: URL?
            if case .logo = skin.texture { logoTile = manager.tileURL(for: skin) }
            result[id.uuidString] = skin.sessionSkin(logoTile: logoTile).encoded
        }
        return result
    }
}

extension Skin {
    /// What the phone draws: the colors and the texture. A logo goes as
    /// the tile drawn of it here (`logoTile`), for the phone to fetch;
    /// without one, it's left off.
    func sessionSkin(logoTile: URL? = nil) -> SessionSkin {
        func rgb(_ c: RGB) -> SessionSkin.RGB { SessionSkin.RGB(r: c.r, g: c.g, b: c.b) }
        var shared: SessionSkin.Texture?
        switch texture {
        case .builtin(let pattern): shared = SessionSkin.Texture(pattern: pattern, opacity: textureOpacity)
        case .logo: shared = logoTile.map { SessionSkin.Texture(look: .logo(tile: $0.path), opacity: textureOpacity) }
        case .none: break
        }
        return SessionSkin(
            background: rgb(background), foreground: foreground.map(rgb), accent: rgb(accent), texture: shared)
    }
}
#endif
