#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SkinManagerTests {
    final class Harness {
        var calls: [(UUID, AppliedSkin?)] = []
        var alive = true
        var clock = Date(timeIntervalSince1970: 1_000_000)
    }

    let root: String
    let arca: Skin
    let prod: Skin
    let config: SkinConfig

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("skins-mgr-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: "\(base)/arca/app", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(base)/Milo/.git", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(base)/plain", withIntermediateDirectories: true)
        root = ProjectResolver.canonical(base)
        arca = Skin(name: "arca", background: RGB(hex: "#12222b")!, foreground: nil,
                    accent: RGB(hex: "#46a2ff")!, texture: .builtin(.dots), textureOpacity: 0.16)
        prod = Skin(name: "prod", background: RGB(hex: "#3a0f14")!, foreground: nil,
                    accent: Skin.defaultAccent(for: RGB(hex: "#3a0f14")!), texture: .builtin(.diagonal), textureOpacity: 0.16)
        var config = SkinConfig()
        config.skins = ["arca": arca, "prod": prod]
        config.matches = [SkinMatch(path: "\(root)/arca", skin: "arca")]
        self.config = config
    }

    func makeManager(_ harness: Harness, catalog: URL? = nil, config: SkinConfig? = nil) -> SkinManager {
        SkinManager(
            config: config ?? self.config,
            textures: TextureStore(cacheDir: URL(fileURLWithPath: root).appendingPathComponent("cache")),
            catalogURL: catalog,
            home: "/nonexistent-home",
            now: { harness.clock },
            apply: { id, applied in
                harness.calls.append((id, applied))
                return harness.alive
            })
    }

    @Test func appliesConfiguredSkinOnceAndRevertsOnLeave() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca/app")
        #expect(h.calls.count == 1)
        #expect(h.calls.last?.1?.skin == arca)
        #expect(h.calls.last?.1?.tile != nil)
        m.pwdChanged(id, pwd: "\(root)/arca")
        #expect(h.calls.count == 1)
        m.pwdChanged(id, pwd: "\(root)/plain")
        #expect(h.calls.count == 2)
        #expect(h.calls.last?.1 == nil)
    }

    @Test func unskinnedPaneIsNeverTouched() {
        let h = Harness(); let m = makeManager(h)
        m.pwdChanged(UUID(), pwd: "\(root)/plain")
        #expect(h.calls.isEmpty)
    }

    @Test func autoSkinForUnlistedRepo() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        #expect(h.calls.last?.1?.skin == AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16))
        #expect(m.sourceLabel(id) == "Auto: Milo")
    }

    @Test func overridePersistsAcrossCdUntilReset() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        let milo = AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16)
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handleUserVar(id, name: SkinsConstants.userVarName, value: #"{"v":1,"op":"set","skin":"prod"}"#)
        #expect(m.effectiveSkin(id) == prod)
        m.pwdChanged(id, pwd: "\(root)/plain")
        #expect(m.effectiveSkin(id) == prod)
        #expect(m.sourceLabel(id) == "Override")
        m.handleUserVar(id, name: SkinsConstants.userVarName, value: #"{"v":1,"op":"reset"}"#)
        m.pwdChanged(id, pwd: "\(root)/Milo")
        #expect(m.effectiveSkin(id) == milo)
        #expect(h.calls.last?.1?.skin == milo)
    }

    @Test func previewAndCancel() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        let milo = AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16)
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .preview, skin: "prod"), for: id)
        #expect(m.effectiveSkin(id) == prod)
        // A second preview replaces the first rather than stacking on it.
        m.handle(SkinRequest(op: .preview, texture: "grid"), for: id)
        #expect(m.effectiveSkin(id)?.background == milo.background)
        #expect(m.effectiveSkin(id)?.texture == .builtin(.grid))
        m.handle(SkinRequest(op: .cancel), for: id)
        #expect(m.effectiveSkin(id) == milo)
    }

    @Test func previewExpires() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        let milo = AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16)
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .preview, skin: "prod"), for: id)
        h.clock += 59
        m.expirePreviews()
        #expect(m.effectiveSkin(id) == prod)
        h.clock += 2
        m.expirePreviews()
        #expect(m.effectiveSkin(id) == milo)
        #expect(h.calls.last?.1?.skin == milo)
    }

    @Test func rejectsUnknownNames() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        let milo = AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16)
        m.pwdChanged(id, pwd: "\(root)/Milo")
        let before = h.calls.count
        m.handle(SkinRequest(op: .set, skin: "missing"), for: id)
        m.handle(SkinRequest(op: .set, texture: "missing"), for: id)
        m.handleUserVar(id, name: "OTHER_VAR", value: #"{"v":1,"op":"set","skin":"prod"}"#)
        m.handleUserVar(id, name: SkinsConstants.userVarName, value: "garbage")
        #expect(h.calls.count == before)
        #expect(m.effectiveSkin(id) == milo)
    }

    @Test func colorOverrideRecomputesBuiltinAccent() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        let red = RGB(hex: "#400000")!
        m.handle(SkinRequest(op: .set, background: red), for: id)
        #expect(m.effectiveSkin(id)?.background == red)
        #expect(m.effectiveSkin(id)?.accent == Skin.defaultAccent(for: red))
        #expect(m.effectiveSkin(id)?.name == "custom")
    }

    @Test func goneSurfacesAreDropped() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        h.alive = false
        m.pwdChanged(id, pwd: "\(root)/arca")
        #expect(m.panes[id] == nil)
    }

    @Test func configChangesReResolvePanes() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        var next = config
        next.matches = []
        next.auto = false
        m.updateConfig(next, error: nil)
        #expect(m.effectiveSkin(id) == nil)
        #expect(h.calls.last?.1 == nil)
        m.updateConfig(next, error: "skins.toml line 3: boom")
        #expect(m.configError == "skins.toml line 3: boom")
    }

    @Test func reapplyAllForcesSkinnedPanesOnly() {
        let h = Harness(); let m = makeManager(h)
        let skinned = UUID(), plain = UUID()
        m.pwdChanged(skinned, pwd: "\(root)/arca")
        m.pwdChanged(plain, pwd: "\(root)/plain")
        h.calls.removeAll()
        m.reapplyAll()
        #expect(h.calls.map(\.0) == [skinned])
    }

    @Test func reapplyForcesOnePane() {
        let h = Harness(); let m = makeManager(h)
        let skinned = UUID(), plain = UUID()
        m.pwdChanged(skinned, pwd: "\(root)/arca")
        m.pwdChanged(plain, pwd: "\(root)/plain")
        h.calls.removeAll()
        m.reapply(skinned)
        #expect(h.calls.count == 1)
        #expect(h.calls.last?.0 == skinned)
        #expect(h.calls.last?.1?.skin == arca)
        m.reapply(plain)
        #expect(h.calls.count == 1)
    }

    @Test func writesCatalog() throws {
        let h = Harness()
        let url = URL(fileURLWithPath: root).appendingPathComponent("state/catalog.json")
        let m = makeManager(h, catalog: url); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "prod"), for: id)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let skins = object?["skins"] as? [[String: String]]
        #expect(skins?.map { $0["name"] } == ["neon-arcade", "sunset-drive", "mint-protocol", "deep-dive", "lava-rush", "bubble-pop", "arca", "prod"])
        #expect((object?["textures"] as? [String]) == BuiltinTexture.allCases.map(\.rawValue))
        let pane = (object?["panes"] as? [String: [String: Any]])?[id.uuidString]
        #expect(pane?["skin"] as? String == "prod")
        #expect(pane?["source"] as? String == "override")
        #expect(pane?["background"] as? String == "#3a0f14")
        #expect(pane?["locked"] as? Bool == false)
    }

    @Test func catalogUpdatesWhenPreviewExpires() throws {
        let h = Harness()
        let url = URL(fileURLWithPath: root).appendingPathComponent("state/catalog.json")
        let m = makeManager(h, catalog: url); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .preview, skin: "prod"), for: id)
        h.clock += 61
        m.expirePreviews()
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let pane = (object?["panes"] as? [String: [String: Any]])?[id.uuidString]
        #expect(pane?["skin"] as? String == "Milo")
        #expect(pane?["source"] as? String == "auto")
        #expect(pane?["locked"] as? Bool == false)
    }

    @Test func textureFailureIsPublished() {
        let h = Harness()
        let broken = Skin(name: "broken", background: RGB(hex: "#123456")!, foreground: nil,
                           accent: RGB(hex: "#abcdef")!, texture: .logo(path: "/nonexistent/logo.svg"), textureOpacity: 0.16)
        var brokenConfig = config
        brokenConfig.skins["broken"] = broken
        brokenConfig.matches = [SkinMatch(path: "\(root)/arca", skin: "broken")]
        let m = makeManager(h, config: brokenConfig); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        #expect(m.textureError?.contains("nonexistent") == true)
        #expect(h.calls.last?.1?.skin == broken)
        #expect(h.calls.last?.1?.tile == nil)
    }

    @Test func thumbnailImageDoesNotPublishErrors() {
        let h = Harness(); let m = makeManager(h)
        let broken = Skin(name: "broken", background: RGB(hex: "#123456")!, foreground: nil,
                           accent: RGB(hex: "#abcdef")!, texture: .logo(path: "/nonexistent/logo.svg"), textureOpacity: 0.16)
        #expect(m.thumbnailImage(for: broken) == nil)
        #expect(m.textureError == nil)
    }

    @Test func lockedFolderIgnoresPreviewAndSet() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        #expect(m.isLocked(id))
        #expect(m.lockedSkinName(id) == "arca")
        let calls = h.calls.count
        m.handle(SkinRequest(op: .preview, skin: "prod"), for: id)
        m.handle(SkinRequest(op: .set, skin: "prod"), for: id)
        m.setPreview(id, prod)
        m.setOverride(id, prod)
        #expect(m.effectiveSkin(id) == arca)
        #expect(m.panes[id]?.override == nil)
        #expect(h.calls.count == calls)
        #expect(m.sourceLabel(id) == "Locked: arca")
    }

    @Test func overrideSurvivesLockedFolder() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "prod"), for: id)
        m.pwdChanged(id, pwd: "\(root)/arca/app")
        #expect(m.effectiveSkin(id) == arca)
        #expect(m.equippedName(id) == "prod")
        m.pwdChanged(id, pwd: "\(root)/plain")
        #expect(m.effectiveSkin(id) == prod)
    }

    @Test func resetStillWorksWhileLocked() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "prod"), for: id)
        m.pwdChanged(id, pwd: "\(root)/arca")
        m.handle(SkinRequest(op: .reset), for: id)
        m.pwdChanged(id, pwd: "\(root)/plain")
        #expect(m.effectiveSkin(id) == nil)
    }

    @Test func requestsCanNameBuiltinPresets() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "neon-arcade"), for: id)
        #expect(m.effectiveSkin(id)?.palette?.count == 16)
        #expect(h.calls.last?.1?.skin.name == "neon-arcade")
    }

    @Test func requestUsesShadowedPreset() {
        var cfg = config
        cfg.skins["neon-arcade"] = Skin(name: "neon-arcade", background: RGB(hex: "#000000")!, foreground: nil,
                                        accent: RGB(hex: "#ffffff")!, texture: .none, textureOpacity: 0.16)
        let h = Harness()
        let m = SkinManager(config: cfg, textures: TextureStore(cacheDir: URL(fileURLWithPath: root).appendingPathComponent("cache")),
                            catalogURL: nil, home: "/nonexistent-home", now: { h.clock },
                            apply: { id, a in h.calls.append((id, a)); return true })
        let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "neon-arcade"), for: id)
        #expect(m.effectiveSkin(id)?.background == RGB(hex: "#000000"))
        #expect(m.effectiveSkin(id)?.palette == nil)
    }

    @Test func matchToABuiltinPresetLocksAndResolves() throws {
        var cfg = config
        cfg.matches.append(SkinMatch(path: "\(root)/plain", skin: "neon-arcade"))
        let h = Harness()
        let m = SkinManager(config: cfg, textures: TextureStore(cacheDir: URL(fileURLWithPath: root).appendingPathComponent("cache")),
                            catalogURL: nil, home: "/nonexistent-home", now: { h.clock },
                            apply: { id, a in h.calls.append((id, a)); return true })
        let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/plain")
        #expect(m.isLocked(id))
        #expect(m.lockedSkinName(id) == "neon-arcade")
        #expect(m.effectiveSkin(id)?.palette?.count == 16)
    }

    @Test func textureRequestOnAPresetKeepsItsAccent() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        m.handle(SkinRequest(op: .set, skin: "neon-arcade"), for: id)
        let accentBefore = m.effectiveSkin(id)?.accent
        m.handle(SkinRequest(op: .set, texture: "rings"), for: id)
        #expect(m.effectiveSkin(id)?.accent == accentBefore)
        #expect(m.effectiveSkin(id)?.palette?.count == 16)
        m.handle(SkinRequest(op: .set, texture: "none"), for: id)
        #expect(m.effectiveSkin(id)?.accent == accentBefore)
    }

    @Test func textureRequestOnAPaletteLessBaseRecomputesAccent() {
        let h = Harness(); let m = makeManager(h); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/Milo")
        let milo = AutoSkin.skin(forRepo: "Milo", textureOpacity: 0.16)
        m.handle(SkinRequest(op: .set, texture: "grid"), for: id)
        #expect(m.effectiveSkin(id)?.accent == Skin.defaultAccent(for: milo.background))
        m.handle(SkinRequest(op: .set, texture: "none"), for: id)
        #expect(m.effectiveSkin(id)?.accent == Skin.defaultAccent(for: milo.background))
    }

    @Test func catalogListsLibraryAndLockedPanes() throws {
        let h = Harness()
        let url = URL(fileURLWithPath: root).appendingPathComponent("state/catalog.json")
        let m = makeManager(h, catalog: url); let id = UUID()
        m.pwdChanged(id, pwd: "\(root)/arca")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let skins = object?["skins"] as? [[String: String]]
        #expect(skins?.first(where: { $0["name"] == "neon-arcade" })?["rarity"] == "legendary")
        #expect(skins?.first(where: { $0["name"] == "arca" })?["rarity"] == "project")
        let pane = (object?["panes"] as? [String: [String: Any]])?[id.uuidString]
        #expect(pane?["locked"] as? Bool == true)
        #expect(pane?["source"] as? String == "config")
        #expect(pane?["skin"] as? String == "arca")
    }
}
#endif
