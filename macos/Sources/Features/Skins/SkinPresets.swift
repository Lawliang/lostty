#if os(macOS)
import Foundation

enum SkinRarity: String {
    case legendary, epic, rare, common, project
}

struct SkinPreset {
    let skin: Skin
    let rarity: SkinRarity
}

/// The built-in preset pack (spec §3). Palettes are hand-tuned: 0/8 dark,
/// 7/15 light, 1–6 and 9–14 vivid and readable on the preset's background.
enum SkinPresets {
    static let all: [SkinPreset] = [
        make("neon-arcade", .legendary, bg: "#120a2a", fg: "#f3ecff", accent: "#ff3df2", accent2: "#28e7ff", texture: .grid,
             palette: ["#1d1240", "#ff4f7b", "#3dffb0", "#ffd84d", "#7b8cff", "#ff3df2", "#28e7ff", "#d9ccff",
                       "#6f6197", "#ff7a9c", "#7dffcb", "#ffe68a", "#a5b1ff", "#ff7af6", "#7af0ff", "#f3ecff"]),
        make("sunset-drive", .epic, bg: "#1c0b24", fg: "#ffe9f5", accent: "#ff7a3d", accent2: "#ff4fa3", texture: .scanlines,
             palette: ["#2b1436", "#ff4f5e", "#9dff6a", "#ffb347", "#8f7bff", "#ff4fa3", "#5ee7ff", "#f0d4e6",
                       "#7d5f84", "#ff7a86", "#bfff96", "#ffcf7f", "#b3a6ff", "#ff85c0", "#8ff0ff", "#ffe9f5"]),
        make("mint-protocol", .rare, bg: "#04140f", fg: "#d8ffe9", accent: "#2cff9a", accent2: "#b6ff3b", texture: .dots,
             palette: ["#0b2219", "#ff5c7a", "#2cff9a", "#b6ff3b", "#3fb8ff", "#d38bff", "#3dffe0", "#bfe8d2",
                       "#4b7161", "#ff8aa0", "#7dffc0", "#d4ff85", "#7fd1ff", "#e3b3ff", "#8affec", "#d8ffe9"]),
        make("deep-dive", .rare, bg: "#041a2e", fg: "#dff4ff", accent: "#25c4ff", accent2: "#9b87ff", texture: .waves,
             palette: ["#0b2a45", "#ff5c8a", "#3dffa8", "#ffd166", "#25c4ff", "#9b87ff", "#3de8ff", "#c4e4f5",
                       "#4f728e", "#ff8aac", "#85ffc8", "#ffe199", "#7ad8ff", "#bfb3ff", "#8af0ff", "#dff4ff"]),
        make("lava-rush", .epic, bg: "#1d0806", fg: "#fff0e8", accent: "#ff5a2c", accent2: "#ffc53d", texture: .diagonal,
             palette: ["#2e110c", "#ff5a2c", "#b8ff4d", "#ffc53d", "#6fa8ff", "#ff5fb0", "#4de3ff", "#f2d9cc",
                       "#856056", "#ff8a66", "#d2ff8a", "#ffd97f", "#9cc4ff", "#ff8fca", "#8aecff", "#fff0e8"]),
        make("bubble-pop", .common, bg: "#230a24", fg: "#ffeefe", accent: "#ff6ad5", accent2: "#ffd84d", texture: .sparkle,
             palette: ["#36143a", "#ff5c8a", "#6dffb3", "#ffd84d", "#7ea8ff", "#ff6ad5", "#5cf2ff", "#f2d6f0",
                       "#855f86", "#ff8aab", "#9dffcc", "#ffe68a", "#a8c4ff", "#ff9be4", "#92f6ff", "#ffeefe"]),
    ]

    /// Display name for a preset id ("neon-arcade" → "Neon Arcade").
    static func displayName(_ id: String) -> String {
        id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func make(
        _ id: String, _ rarity: SkinRarity, bg: String, fg: String, accent: String, accent2: String,
        texture: BuiltinTexture, palette: [String]
    ) -> SkinPreset {
        let background = RGB(hex: bg)!
        let accentRGB = RGB(hex: accent)!
        return SkinPreset(
            skin: Skin(
                name: id, background: background, foreground: RGB(hex: fg)!, accent: accentRGB,
                texture: .builtin(texture), textureOpacity: 0.22,
                accent2: RGB(hex: accent2)!, palette: palette.map { RGB(hex: $0)! },
                cursor: accentRGB, selectionBackground: background.mixed(with: accentRGB, amount: 0.35)),
            rarity: rarity)
    }
}

/// Built-in presets merged with skins.toml skins; config skins shadow built-ins.
enum SkinLibrary {
    struct Entry {
        let skin: Skin
        let rarity: SkinRarity
    }

    static func entries(config: SkinConfig) -> [Entry] {
        var result = SkinPresets.all.map { preset -> Entry in
            if let own = config.skins[preset.skin.name] { return Entry(skin: own, rarity: .project) }
            // Config skins keep their own texture_opacity (already resolved by
            // SkinConfig.parse); built-in presets pick up skins.toml's default.
            var skin = preset.skin
            skin.textureOpacity = config.textureOpacity
            return Entry(skin: skin, rarity: preset.rarity)
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
