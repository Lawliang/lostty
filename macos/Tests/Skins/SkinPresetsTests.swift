#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SkinPresetsTests {
    @Test func packMatchesSpec() {
        #expect(SkinPresets.arcade.map(\.skin.name) == ["neon-arcade", "sunset-drive", "mint-protocol", "deep-dive", "lava-rush", "bubble-pop"])
        #expect(SkinPresets.arcade.map(\.rarity) == [.legendary, .epic, .rare, .rare, .epic, .common])
        let neon = SkinPresets.arcade[0].skin
        #expect(neon.background == RGB(hex: "#120a2a"))
        #expect(neon.foreground == RGB(hex: "#f3ecff"))
        #expect(neon.accent == RGB(hex: "#ff3df2"))
        #expect(neon.accent2 == RGB(hex: "#28e7ff"))
        #expect(neon.texture == .builtin(.grid))
    }

    @Test func boonPackHasOnePatronEach() {
        let boons = SkinPresets.boons
        #expect(boons.map(\.skin.name) == ["thunderhead", "undertow", "bloodrite", "heartsease", "silverbow", "stormsurge"])
        #expect(boons.map(\.rarity) == [.epic, .rare, .heroic, .common, .legendary, .duo])
        #expect(boons.map(\.patron) == ["Zeus", "Poseidon", "Ares", "Aphrodite", "Artemis", "Zeus & Poseidon"])
        #expect(boons.map(\.skin.texture) == [.lightning, .tide, .blades, .petals, .starfield, .tempest].map { .builtin($0) })
        #expect(SkinPresets.all.map(\.skin.name) == boons.map(\.skin.name) + SkinPresets.arcade.map(\.skin.name))
    }

    @Test func everyPresetHasABlurb() {
        for preset in SkinPresets.all {
            #expect(!preset.blurb.isEmpty, "\(preset.skin.name)")
        }
    }

    @Test func libraryCarriesPresetMetadata() {
        let entries = SkinLibrary.entries(config: .empty)
        let thunderhead = entries.first { $0.skin.name == "thunderhead" }
        #expect(thunderhead?.patron == "Zeus")
        #expect(thunderhead?.glyph == .bolt)
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
        #expect(entries.map(\.skin.name) == SkinPresets.all.map(\.skin.name) + ["arca"])
        #expect(entries.last?.rarity == .project)
        #expect(entries.last?.glyph == .sigil)
        #expect(SkinLibrary.skins(config: config).count == SkinPresets.all.count + 1)
    }

    @Test func configShadowsBuiltin() throws {
        let config = try SkinConfig.parse("[skins.neon-arcade]\nbackground = \"#000000\"", home: "/h")
        let entries = SkinLibrary.entries(config: config)
        #expect(entries.count == SkinPresets.all.count)
        let neon = try #require(entries.first { $0.skin.name == "neon-arcade" })
        #expect(neon.skin.background == RGB(hex: "#000000"))
        #expect(neon.rarity == .project)
        #expect(SkinLibrary.skins(config: config)["neon-arcade"]?.palette == nil)
    }

    @Test func textureOpacityFromConfigAppliesToBuiltinsOnly() throws {
        let config = try SkinConfig.parse("""
        [defaults]
        texture_opacity = 0.4

        [skins.arca]
        background = "#12222b"
        texture_opacity = 0.1
        """, home: "/h")
        let entries = SkinLibrary.entries(config: config)
        #expect(entries.first(where: { $0.skin.name == "neon-arcade" })?.skin.textureOpacity == 0.4)
        #expect(entries.first(where: { $0.skin.name == "arca" })?.skin.textureOpacity == 0.1)
    }

    /// Palette readability (spec §3): ANSI 8 must read at ≥3:1 against the
    /// preset's own background (WCAG relative luminance).
    @Test func palette8IsReadableAgainstBackground() {
        for preset in SkinPresets.all {
            let color = preset.skin.palette?[8]
            #expect(color != nil, "\(preset.skin.name)")
            guard let color else { continue }
            #expect(contrastRatio(preset.skin.background, color) >= 3.0, "\(preset.skin.name)")
        }
    }

    private func relativeLuminance(_ c: RGB) -> Double {
        func channel(_ v: UInt8) -> Double {
            let s = Double(v) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let l1 = relativeLuminance(a), l2 = relativeLuminance(b)
        let lighter = max(l1, l2), darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
#endif
