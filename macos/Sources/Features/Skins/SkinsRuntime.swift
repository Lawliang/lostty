#if os(macOS)
import AppKit
import Foundation
import GhosttyKit

/// The Ghostty config lines a skin adds on top of the user's config.
enum SkinOverlay {
    static func configText(for applied: AppliedSkin) -> String {
        var lines = ["background = \(applied.skin.background.hex)"]
        if let foreground = applied.skin.foreground {
            lines.append("foreground = \(foreground.hex)")
        }
        if let tile = applied.tile {
            lines.append("background-image = \"\(tile.path)\"")
            lines.append(String(format: "background-image-opacity = %.3f", applied.skin.textureOpacity))
            lines.append("background-image-fit = none")
            lines.append("background-image-position = top-left")
            lines.append("background-image-repeat = true")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Applies a skin to one surface: user config + overlay → ghostty_surface_update_config.
@MainActor
final class GhosttySkinApplier {
    private let overlayDir: URL

    init(overlayDir: URL) {
        self.overlayDir = overlayDir
    }

    func apply(_ id: UUID, _ applied: AppliedSkin?) -> Bool {
        guard let delegate = NSApp.delegate as? GhosttyAppDelegate,
              let view = delegate.findSurface(forUUID: id),
              let surface = view.surface else { return false }
        guard let cfg = ghostty_config_new() else { return true }
        defer { ghostty_config_free(cfg) }

        ghostty_config_load_default_files(cfg)
        if !isRunningInXcode() { ghostty_config_load_cli_args(cfg) }
        ghostty_config_load_recursive_files(cfg)
        if let applied {
            // Ghostty Skins: the overlay loads after the user's own
            // `config-file =` includes so the skin always wins.
            let url = overlayDir.appendingPathComponent("\(id.uuidString).ghostty")
            do {
                try FileManager.default.createDirectory(at: overlayDir, withIntermediateDirectories: true)
                try SkinOverlay.configText(for: applied).write(to: url, atomically: true, encoding: .utf8)
                ghostty_config_load_file(cfg, url.path)
            } catch {
                Ghostty.logger.warning("skins: failed to write overlay: \(String(describing: error))")
            }
        }
        ghostty_config_finalize(cfg)
        ghostty_surface_update_config(surface, cfg)
        return true
    }
}

/// App-wide skins wiring: config store, manager, applier, preview expiry.
@MainActor
final class SkinsRuntime {
    static let shared = SkinsRuntime()

    static var configDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/ghostty-skins")
    }

    static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ghostty-skins")
    }

    let manager: SkinManager
    private let store: SkinConfigStore
    private var expiryTimer: Timer?

    private init() {
        let overlayDir = Self.cacheDir.appendingPathComponent("overlays")
        let applier = GhosttySkinApplier(overlayDir: overlayDir)
        let store = SkinConfigStore(fileURL: Self.configDir.appendingPathComponent("skins.toml"))
        store.reload()
        self.store = store
        let textures = TextureStore(cacheDir: Self.cacheDir.appendingPathComponent("textures"))
        // Ghostty Skins: keep the on-disk caches from growing without bound.
        textures.prune()
        TextureStore.pruneOldFiles(in: overlayDir, olderThan: 7 * 24 * 3600)
        self.manager = SkinManager(
            config: store.config,
            textures: textures,
            catalogURL: Self.configDir.appendingPathComponent("state/catalog.json"),
            apply: { id, applied in applier.apply(id, applied) })
        manager.updateConfig(store.config, error: store.error)
        store.onChange = { [weak self] in
            guard let self else { return }
            self.manager.updateConfig(self.store.config, error: self.store.error)
        }
        store.startWatching()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.manager.expirePreviews() }
        }
    }

    func pwdChanged(_ view: Ghostty.SurfaceView, pwd: String) {
        manager.pwdChanged(view.id, pwd: pwd)
    }

    func userVarChanged(_ view: Ghostty.SurfaceView, name: String, value: String) {
        manager.handleUserVar(view.id, name: name, value: value)
    }

    func ghosttyConfigReloaded() {
        manager.reapplyAll()
    }

    /// A per-surface config reload (e.g. macOS's soft reload on a light/dark
    /// appearance change) replaced this surface's config with the global one;
    /// put its skin back.
    func surfaceConfigReloaded(_ view: Ghostty.SurfaceView) {
        manager.reapply(view.id)
    }
}
#endif
