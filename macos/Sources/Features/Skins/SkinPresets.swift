#if os(macOS)
import Foundation

enum SkinRarity: String {
    case legendary, heroic, epic, rare, common, duo, project
}

/// The emblem drawn in a skin's boon frame (see `SkinGlyphShape`).
enum SkinGlyph {
    case bolt, trident, sword, heart, moon, stormsea, spark, sigil
}

struct SkinPreset {
    let skin: Skin
    let rarity: SkinRarity
    /// The god offering this skin in the boon picker, or nil for the
    /// original arcade pack.
    var patron: String? = nil
    var glyph: SkinGlyph = .spark
    /// One-line description shown under the name in the picker.
    var blurb: String = ""
}

/// The built-in preset pack (spec §3). Palettes are hand-tuned: 0/8 dark,
/// 7/15 light, 1–6 and 9–14 vivid and readable on the preset's background.
enum SkinPresets {
    static let all: [SkinPreset] = boons + arcade

    static let arcade: [SkinPreset] = [
        make("neon-arcade", .legendary, bg: "#120a2a", fg: "#f3ecff", accent: "#ff3df2", accent2: "#28e7ff", texture: .grid, trace: .comet,
             blurb: "Bright magenta and cyan on a dark purple grid.",
             palette: ["#1d1240", "#ff4f7b", "#3dffb0", "#ffd84d", "#7b8cff", "#ff3df2", "#28e7ff", "#d9ccff",
                       "#6f6197", "#ff7a9c", "#7dffcb", "#ffe68a", "#a5b1ff", "#ff7af6", "#7af0ff", "#f3ecff"]),
        make("sunset-drive", .epic, bg: "#1c0b24", fg: "#ffe9f5", accent: "#ff7a3d", accent2: "#ff4fa3", texture: .scanlines, trace: .sunset,
             blurb: "Warm orange and pink on a dark plum with scanlines.",
             palette: ["#2b1436", "#ff4f5e", "#9dff6a", "#ffb347", "#8f7bff", "#ff4fa3", "#5ee7ff", "#f0d4e6",
                       "#7d5f84", "#ff7a86", "#bfff96", "#ffcf7f", "#b3a6ff", "#ff85c0", "#8ff0ff", "#ffe9f5"]),
        make("mint-protocol", .rare, bg: "#04140f", fg: "#d8ffe9", accent: "#2cff9a", accent2: "#b6ff3b", texture: .dots, trace: .datastream,
             blurb: "Neon green and yellow on a dark teal.",
             palette: ["#0b2219", "#ff5c7a", "#2cff9a", "#b6ff3b", "#3fb8ff", "#d38bff", "#3dffe0", "#bfe8d2",
                       "#4b7161", "#ff8aa0", "#7dffc0", "#d4ff85", "#7fd1ff", "#e3b3ff", "#8affec", "#d8ffe9"]),
        make("deep-dive", .rare, bg: "#041a2e", fg: "#dff4ff", accent: "#25c4ff", accent2: "#9b87ff", texture: .waves, trace: .sonar,
             blurb: "Bright cyan and purple on a dark blue.",
             palette: ["#0b2a45", "#ff5c8a", "#3dffa8", "#ffd166", "#25c4ff", "#9b87ff", "#3de8ff", "#c4e4f5",
                       "#4f728e", "#ff8aac", "#85ffc8", "#ffe199", "#7ad8ff", "#bfb3ff", "#8af0ff", "#dff4ff"]),
        make("lava-rush", .epic, bg: "#1d0806", fg: "#fff0e8", accent: "#ff5a2c", accent2: "#ffc53d", texture: .diagonal, trace: .ember,
             blurb: "Warm orange and yellow on a dark brown.",
             palette: ["#2e110c", "#ff5a2c", "#b8ff4d", "#ffc53d", "#6fa8ff", "#ff5fb0", "#4de3ff", "#f2d9cc",
                       "#856056", "#ff8a66", "#d2ff8a", "#ffd97f", "#9cc4ff", "#ff8fca", "#8aecff", "#fff0e8"]),
        make("bubble-pop", .common, bg: "#230a24", fg: "#ffeefe", accent: "#ff6ad5", accent2: "#ffd84d", texture: .sparkle, trace: .bubbles,
             blurb: "Hot pink and yellow on a purple with sparkles.",
             palette: ["#36143a", "#ff5c8a", "#6dffb3", "#ffd84d", "#7ea8ff", "#ff6ad5", "#5cf2ff", "#f2d6f0",
                       "#855f86", "#ff8aab", "#9dffcc", "#ffe68a", "#a8c4ff", "#ff9be4", "#92f6ff", "#ffeefe"]),
    ]

    /// The Olympian boon pack: one skin per patron, plus a Duo.
    static let boons: [SkinPreset] = [
        make("thunderhead", .epic, bg: "#0b1430", fg: "#dfe7ff", accent: "#ffd84a", accent2: "#7fc8ff", texture: .lightning, trace: .bolt,
             patron: "Zeus", glyph: .bolt,
             blurb: "Storm navy laced with forked lightning; cursor strikes in thunder gold.",
             palette: ["#16224a", "#ff5d6c", "#8be38a", "#ffd84a", "#7fc8ff", "#c9a0ff", "#7fe9ff", "#c8d2ee",
                       "#6f7ea8", "#ff8a95", "#b3f0b2", "#ffe68a", "#a8dbff", "#ddc2ff", "#a8f2ff", "#dfe7ff"]),
        make("undertow", .rare, bg: "#04212b", fg: "#d6f6f2", accent: "#3fe0d0", accent2: "#59b8ff", texture: .tide, trace: .tide,
             patron: "Poseidon", glyph: .trident,
             blurb: "Abyssal teal rolling with slow tide lines; prompts surface in sea-foam.",
             palette: ["#0b3440", "#ff7a6b", "#5fe3a1", "#f2e48a", "#59b8ff", "#b49cff", "#3fe0d0", "#bfe3df",
                       "#5f8f93", "#ff9d92", "#93edc0", "#f7eeb0", "#8ccfff", "#cdbdff", "#7debe0", "#d6f6f2"]),
        make("bloodrite", .heroic, bg: "#1c0506", fg: "#f3dcd8", accent: "#ff3b3f", accent2: "#ffb547", texture: .blades, trace: .blade,
             patron: "Ares", glyph: .sword,
             blurb: "A dried-blood ground crossed with blade marks; cursor in battle red.",
             palette: ["#2e0c0d", "#ff3b3f", "#a8d672", "#ffb547", "#8fb0d9", "#e07ab0", "#9fd4d0", "#e2c8c3",
                       "#8a5a57", "#ff6e6f", "#c6e89c", "#ffcd80", "#b4cbe8", "#eda2c8", "#c0e6e3", "#f3dcd8"]),
        make("heartsease", .common, bg: "#260b1e", fg: "#ffe3f0", accent: "#ff7ab8", accent2: "#ffd59a", texture: .petals, trace: .petal,
             patron: "Aphrodite", glyph: .heart,
             blurb: "Dusk rose scattered with drifting petals; selection blooms rose pink.",
             palette: ["#3a1530", "#ff6b8a", "#9be7b0", "#ffd59a", "#a9b8ff", "#ff7ab8", "#9ee8e8", "#f0cfe0",
                       "#9a6f86", "#ff95ab", "#bff0cc", "#ffe3bb", "#c6d0ff", "#ffa3cd", "#c0f0f0", "#ffe3f0"]),
        make("silverbow", .legendary, bg: "#06160f", fg: "#e4f2e6", accent: "#8ff08a", accent2: "#c9d6e8", texture: .starfield, trace: .arrow,
             patron: "Artemis", glyph: .moon,
             blurb: "Night-forest green under a starfield and crescent moon; cursor in hunter green.",
             palette: ["#0f2a1e", "#ff7b6e", "#8ff08a", "#e8f0a0", "#9cc8ff", "#d6b3ff", "#a8f0d8", "#cfe0d2",
                       "#5e8a70", "#ff9f95", "#b5f5b1", "#f0f5c0", "#bddbff", "#e4ccff", "#c6f5e6", "#e4f2e6"]),
        make("stormsurge", .duo, bg: "#061a26", fg: "#def4f6", accent: "#ffd84a", accent2: "#3fe0d0", texture: .tempest, trace: .tempest,
             patron: "Zeus & Poseidon", glyph: .stormsea,
             blurb: "Lightning over open water: gold strikes above teal swells, layered.",
             palette: ["#0e2c3c", "#ff6b6b", "#6fe3a8", "#ffd84a", "#6fbaff", "#c2a0ff", "#3fe0d0", "#c3dfe4",
                       "#5a8396", "#ff9393", "#9cedc4", "#ffe68a", "#9cd0ff", "#d8c2ff", "#7debe0", "#def4f6"]),
    ]

    /// Display name for a preset id ("neon-arcade" → "Neon Arcade").
    static func displayName(_ id: String) -> String {
        id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Title shown for a skin: the friendly display name only when it really
    /// is a preset (its name matches a preset id *and* it still carries that
    /// preset's palette, i.e. it wasn't shadowed by a paletteless config skin
    /// of the same name); otherwise the raw name.
    static func title(for skin: Skin) -> String {
        guard skin.palette != nil, all.contains(where: { $0.skin.name == skin.name }) else { return skin.name }
        return displayName(skin.name)
    }

    private static func make(
        _ id: String, _ rarity: SkinRarity, bg: String, fg: String, accent: String, accent2: String,
        texture: BuiltinTexture, trace: BuiltinTrace, patron: String? = nil, glyph: SkinGlyph = .spark, blurb: String,
        palette: [String]
    ) -> SkinPreset {
        let background = RGB(hex: bg)!
        let accentRGB = RGB(hex: accent)!
        return SkinPreset(
            skin: Skin(
                name: id, background: background, foreground: RGB(hex: fg)!, accent: accentRGB,
                texture: .builtin(texture), textureOpacity: 0.22,
                accent2: RGB(hex: accent2)!, palette: palette.map { RGB(hex: $0)! },
                cursor: accentRGB, selectionBackground: background.mixed(with: accentRGB, amount: 0.35),
                trace: SkinTrace(style: trace)),
            rarity: rarity, patron: patron, glyph: glyph, blurb: blurb)
    }
}

/// Built-in presets merged with skins.toml skins; config skins shadow built-ins.
enum SkinLibrary {
    struct Entry {
        let skin: Skin
        let rarity: SkinRarity
        var patron: String? = nil
        var glyph: SkinGlyph = .sigil
        var blurb: String = "From skins.toml."
    }

    static func entries(config: SkinConfig) -> [Entry] {
        var result = SkinPresets.all.map { preset -> Entry in
            if var own = config.skins[preset.skin.name] {
                // A config skin shadowing a preset keeps the preset's trace
                // style unless it picks its own (or turns it off).
                if own.trace?.style == nil, own.trace?.disabled != true {
                    var trace = own.trace ?? SkinTrace()
                    trace.style = preset.skin.trace?.style
                    own.trace = trace
                }
                return Entry(skin: own, rarity: .project)
            }
            // Config skins keep their own texture_opacity (already resolved by
            // SkinConfig.parse); built-in presets pick up skins.toml's default.
            var skin = preset.skin
            skin.textureOpacity = config.textureOpacity
            return Entry(skin: skin, rarity: preset.rarity, patron: preset.patron, glyph: preset.glyph, blurb: preset.blurb)
        }
        let builtinNames = Set(SkinPresets.all.map(\.skin.name))
        for skin in config.skins.values.sorted(by: { $0.name < $1.name }) where !builtinNames.contains(skin.name) {
            result.append(Entry(skin: skin, rarity: .project))
        }
        return result
    }

    static func skins(config: SkinConfig) -> [String: Skin] {
        Dictionary(uniqueKeysWithValues: entries(config: config).map { ($0.skin.name, $0.skin) })
    }
}
#endif
