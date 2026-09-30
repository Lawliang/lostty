#if os(macOS)
import Combine
import CoreGraphics
import Foundation

struct AppliedSkin: Hashable {
    var skin: Skin
    var tile: URL?
}

/// Owns every pane's skin state; the only component that changes how panes look.
/// Layers, first match wins (spec §2): mapped skin (locked) → preview (transient)
/// → override (sticky) → automatic git-repo skin → default look.
@MainActor
final class SkinManager: ObservableObject {
    struct Pane: Equatable {
        var pwd: String?
        var source: SkinSource = .none
        var override: Skin?
        var preview: Skin?
        var previewUpdatedAt: Date?
        /// nil = never applied; `.some(nil)` = the user's normal look is applied.
        var lastApplied: AppliedSkin??
    }

    /// Applies a look to a surface. Returns false when the surface no longer exists.
    typealias Applier = @MainActor (UUID, AppliedSkin?) -> Bool

    static let previewTimeout: TimeInterval = 60

    @Published private(set) var config: SkinConfig
    @Published private(set) var configError: String?
    @Published private(set) var panes: [UUID: Pane] = [:]
    @Published private(set) var textureError: String?

    private let textures: TextureStore
    private let catalogURL: URL?
    private let home: String
    private let now: () -> Date
    private let apply: Applier
    private var resolver: ProjectResolver

    init(
        config: SkinConfig,
        textures: TextureStore,
        catalogURL: URL?,
        home: String = NSHomeDirectory(),
        now: @escaping () -> Date = Date.init,
        apply: @escaping Applier
    ) {
        self.config = config
        self.textures = textures
        self.catalogURL = catalogURL
        self.home = home
        self.now = now
        self.apply = apply
        self.resolver = ProjectResolver(matches: config.matches, auto: config.auto, home: home)
    }

    // MARK: Inputs

    func updateConfig(_ config: SkinConfig, error: String?) {
        configError = error
        if config != self.config {
            self.config = config
            resolver = ProjectResolver(matches: config.matches, auto: config.auto, home: home)
            for (id, pane) in panes {
                if let pwd = pane.pwd { panes[id]?.source = resolver.resolve(pwd: pwd) }
                applyIfNeeded(id)
            }
        }
        writeCatalog()
    }

    func pwdChanged(_ id: UUID, pwd: String) {
        var pane = panes[id] ?? Pane()
        pane.pwd = pwd
        pane.source = resolver.resolve(pwd: pwd)
        panes[id] = pane
        applyIfNeeded(id)
        writeCatalog()
    }

    func handleUserVar(_ id: UUID, name: String, value: String) {
        guard name == SkinsConstants.userVarName else { return }
        guard let request = SkinRequest.decode(value) else {
            // Spec §7: invalid CLI messages are ignored, logged at debug level.
            Ghostty.logger.debug("skins: rejected malformed \(SkinsConstants.userVarName) payload")
            return
        }
        handle(request, for: id)
    }

    func handle(_ request: SkinRequest, for id: UUID) {
        var pane = panes[id] ?? Pane()
        switch request.op {
        case .cancel:
            pane.preview = nil
            pane.previewUpdatedAt = nil
        case .reset:
            pane.preview = nil
            pane.previewUpdatedAt = nil
            pane.override = nil
        case .preview:
            if isLocked(id) {
                Ghostty.logger.debug("skins: ignored \(request.op.rawValue) in a locked folder")
                return
            }
            guard let skin = skin(from: request, base: pane.override ?? autoSkin(for: pane.source)) else {
                Ghostty.logger.debug("skins: rejected preview request naming an unknown skin/texture")
                return
            }
            pane.preview = skin
            pane.previewUpdatedAt = now()
        case .set:
            if isLocked(id) {
                Ghostty.logger.debug("skins: ignored \(request.op.rawValue) in a locked folder")
                return
            }
            guard let skin = skin(from: request, base: pane.override ?? autoSkin(for: pane.source)) else {
                Ghostty.logger.debug("skins: rejected set request naming an unknown skin/texture")
                return
            }
            pane.override = skin
            pane.preview = nil
            pane.previewUpdatedAt = nil
        }
        panes[id] = pane
        applyIfNeeded(id)
        writeCatalog()
    }

    /// UI entry points (the popover builds `Skin` values directly).
    func setPreview(_ id: UUID, _ skin: Skin?) {
        if skin != nil, isLocked(id) { return }
        var pane = panes[id] ?? Pane()
        pane.preview = skin
        pane.previewUpdatedAt = skin == nil ? nil : now()
        panes[id] = pane
        applyIfNeeded(id)
        writeCatalog()
    }

    func setOverride(_ id: UUID, _ skin: Skin?) {
        if skin != nil, isLocked(id) { return }
        var pane = panes[id] ?? Pane()
        pane.override = skin
        pane.preview = nil
        pane.previewUpdatedAt = nil
        panes[id] = pane
        applyIfNeeded(id)
        writeCatalog()
    }

    func reset(_ id: UUID) {
        handle(SkinRequest(op: .reset), for: id)
    }

    func expirePreviews() {
        let cutoff = now().addingTimeInterval(-Self.previewTimeout)
        var expired = false
        for (id, pane) in panes where pane.preview != nil && (pane.previewUpdatedAt ?? .distantPast) < cutoff {
            panes[id]?.preview = nil
            panes[id]?.previewUpdatedAt = nil
            applyIfNeeded(id)
            expired = true
        }
        if expired { writeCatalog() }
    }

    /// Re-applies one pane's skin, e.g. after Ghostty replaced that surface's
    /// config with the global one (a per-surface config reload, including the
    /// soft reload macOS sends on a light/dark appearance change).
    func reapply(_ id: UUID) {
        guard effectiveSkin(id) != nil else { return }
        applyIfNeeded(id, force: true)
    }

    /// Re-applies every skinned pane, e.g. after Ghostty reloaded its config
    /// and replaced each surface's config with the global one.
    func reapplyAll() {
        for id in panes.keys.sorted(by: { $0.uuidString < $1.uuidString }) where effectiveSkin(id) != nil {
            applyIfNeeded(id, force: true)
        }
        writeCatalog()
    }

    // MARK: Queries

    /// Built-in presets merged with skins.toml skins (config shadows built-ins).
    var library: [SkinLibrary.Entry] { SkinLibrary.entries(config: config) }

    /// A folder mapped in skins.toml always shows its mapped skin (spec §2).
    func isLocked(_ id: UUID) -> Bool { lockedSkinName(id) != nil }

    func lockedSkinName(_ id: UUID) -> String? {
        guard case .configured(let name)? = panes[id]?.source, config.skins[name] != nil else { return nil }
        return name
    }

    /// The pane's sticky pick, kept even while a locked folder hides it.
    func equippedName(_ id: UUID) -> String? { panes[id]?.override?.name }

    func effectiveSkin(_ id: UUID) -> Skin? {
        guard let pane = panes[id] else { return nil }
        if let locked = lockedSkinName(id) { return config.skins[locked] }
        return pane.preview ?? pane.override ?? autoSkin(for: pane.source)
    }

    func sourceLabel(_ id: UUID) -> String {
        guard let pane = panes[id] else { return "Default" }
        if let locked = lockedSkinName(id) { return "Locked: \(locked)" }
        if pane.preview != nil { return "Preview" }
        if pane.override != nil { return "Override" }
        switch pane.source {
        case .configured(let name): return "Config: \(name)"
        case .auto(let repo): return "Auto: \(repo)"
        case .none: return "Default"
        }
    }

    func tileURL(for skin: Skin) -> URL? {
        do {
            let url = try textures.tileURL(for: skin)
            if skin.texture != .none { textureError = nil }
            return url
        } catch {
            textureError = "\(skin.name): \(String(describing: error))"
            Ghostty.logger.warning("skins: texture for \(skin.name) failed: \(String(describing: error))")
            return nil
        }
    }

    /// Side-effect-free variant of `tileURL(for:)` for use from SwiftUI view
    /// bodies (e.g. the popover's thumbnails), which must not mutate
    /// `@Published` state during a view update. Renders in memory only (no
    /// disk write), so re-previewing colors/textures doesn't grow the
    /// texture cache.
    func thumbnailImage(for skin: Skin) -> CGImage? {
        try? textures.thumbnailImage(for: skin)
    }

    // MARK: Internals

    private func autoSkin(for source: SkinSource) -> Skin? {
        switch source {
        case .configured(let name): return config.skins[name]
        case .auto(let repo): return AutoSkin.skin(forRepo: repo, textureOpacity: config.textureOpacity)
        case .none: return nil
        }
    }

    /// Builds the skin a request asks for, or nil if it names something unknown.
    private func skin(from request: SkinRequest, base: Skin?) -> Skin? {
        let library = SkinLibrary.skins(config: config)
        var skin: Skin
        if let name = request.skin {
            guard let named = library[name] else { return nil }
            skin = named
        } else {
            skin = base ?? Skin.fallback
            if base == nil { skin.textureOpacity = config.textureOpacity }
            skin.name = "custom"
        }
        if let background = request.background {
            skin.background = background
            // Recompute the accent only for skins without a theme; a preset's
            // palette-tuned accent shouldn't be clobbered by a background tweak.
            if case .builtin = skin.texture, skin.palette == nil { skin.accent = Skin.defaultAccent(for: background) }
        }
        if let texture = request.texture {
            if texture == "none" {
                skin.texture = .none
            } else if let builtin = BuiltinTexture(rawValue: texture) {
                skin.texture = .builtin(builtin)
                skin.accent = Skin.defaultAccent(for: skin.background)
            } else if let named = library[texture], named.texture != .none {
                skin.texture = named.texture
                skin.accent = named.accent
            } else {
                return nil
            }
        }
        if let opacity = request.opacity { skin.textureOpacity = opacity }
        return skin
    }

    private func applyIfNeeded(_ id: UUID, force: Bool = false) {
        guard var pane = panes[id] else { return }
        let target = effectiveSkin(id).map { AppliedSkin(skin: $0, tile: tileURL(for: $0)) }
        if !force, let last = pane.lastApplied, last == target { return }
        if pane.lastApplied == nil, target == nil {
            // Never skinned and nothing to show: leave the surface alone.
            pane.lastApplied = .some(nil)
            panes[id] = pane
            return
        }
        if apply(id, target) {
            pane.lastApplied = .some(target)
            panes[id] = pane
        } else {
            panes[id] = nil
        }
    }

    private func sourceKind(_ id: UUID) -> String {
        guard let pane = panes[id] else { return "none" }
        if isLocked(id) { return "config" }
        if pane.preview != nil { return "preview" }
        if pane.override != nil { return "override" }
        switch pane.source {
        case .configured: return "config"
        case .auto: return "auto"
        case .none: return "none"
        }
    }

    private struct Catalog: Encodable {
        struct SkinEntry: Encodable {
            let name: String
            let background: String
            let texture: String
            let rarity: String
        }
        struct PaneEntry: Encodable {
            let skin: String
            let source: String
            let background: String
            let locked: Bool
        }
        let version: Int
        let skins: [SkinEntry]
        let textures: [String]
        let panes: [String: PaneEntry]
    }

    /// Writes catalog.json for the `skins` CLI (skins, textures, each pane's skin).
    func writeCatalog() {
        guard let catalogURL else { return }
        let skins = library.map {
            Catalog.SkinEntry(
                name: $0.skin.name, background: $0.skin.background.hex,
                texture: Self.textureName($0.skin.texture), rarity: $0.rarity.rawValue)
        }
        var paneEntries: [String: Catalog.PaneEntry] = [:]
        for id in panes.keys {
            guard let skin = effectiveSkin(id) else { continue }
            paneEntries[id.uuidString] = .init(
                skin: skin.name, source: sourceKind(id), background: skin.background.hex, locked: isLocked(id))
        }
        let catalog = Catalog(
            version: 1, skins: skins,
            textures: BuiltinTexture.allCases.map(\.rawValue), panes: paneEntries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
        } catch {
            Ghostty.logger.warning("skins: failed to write catalog: \(String(describing: error))")
        }
    }

    private static func textureName(_ texture: SkinTexture) -> String {
        switch texture {
        case .none: return "none"
        case .builtin(let builtin): return builtin.rawValue
        case .logo: return "logo"
        }
    }
}
#endif
