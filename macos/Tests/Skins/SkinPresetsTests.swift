#if os(macOS)
import Testing
@testable import Ghostty

struct SkinPresetsTests {
    @Test func packMatchesSpec() {
        #expect(SkinPresets.all.map(\.skin.name) == ["neon-arcade", "sunset-drive", "mint-protocol", "deep-dive", "lava-rush", "bubble-pop"])
        #expect(SkinPresets.all.map(\.rarity) == [.legendary, .epic, .rare, .rare, .epic, .common])
        let neon = SkinPresets.all[0].skin
        #expect(neon.background == RGB(hex: "#120a2a"))
        #expect(neon.foreground == RGB(hex: "#f3ecff"))
        #expect(neon.accent == RGB(hex: "#ff3df2"))
        #expect(neon.accent2 == RGB(hex: "#28e7ff"))
        #expect(neon.texture == .builtin(.grid))
    }

    @Test func everyPresetHasAFullTheme() {
        for preset in SkinPresets.all {
            #expect(preset.skin.palette?.count == 16, "\(preset.skin.name)")
            #expect(preset.skin.cursor == preset.skin.accent)
            #expect(preset.skin.selectionBackground == preset.skin.background.mixed(with: preset.skin.accent, amount: 0.35))
        }
    }

    @Test func libraryAppendsConfigSkinsAsProject() throws {
        let config = try SkinConfig.parse("[skins.arca]\nbackground = \"#12222b\"", home: "/h")
        let entries = SkinLibrary.entries(config: config)
        #expect(entries.map(\.skin.name) == ["neon-arcade", "sunset-drive", "mint-protocol", "deep-dive", "lava-rush", "bubble-pop", "arca"])
        #expect(entries.last?.rarity == .project)
        #expect(SkinLibrary.skins(config: config).count == 7)
    }

    @Test func configShadowsBuiltin() throws {
        let config = try SkinConfig.parse("[skins.neon-arcade]\nbackground = \"#000000\"", home: "/h")
        let entries = SkinLibrary.entries(config: config)
        #expect(entries.count == 6)
        #expect(entries[0].skin.background == RGB(hex: "#000000"))
        #expect(entries[0].rarity == .project)
        #expect(SkinLibrary.skins(config: config)["neon-arcade"]?.palette == nil)
    }
}
#endif
