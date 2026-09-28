#if os(macOS)
import Foundation

/// Deterministic skins for git repos that skins.toml does not mention.
enum AutoSkin {
    /// 64-bit FNV-1a. Stable across launches, unlike `hashValue`.
    static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    static func skin(forRepo name: String, textureOpacity: Double) -> Skin {
        let hash = fnv1a(name.lowercased())
        let hue = Double(hash % 360)
        let textures = BuiltinTexture.allCases
        return Skin(
            name: name,
            background: .hsl(hue, 0.35, 0.13),
            foreground: nil,
            accent: .hsl(hue, 0.55, 0.62),
            texture: .builtin(textures[Int((hash >> 16) % UInt64(textures.count))]),
            textureOpacity: textureOpacity)
    }
}
#endif
