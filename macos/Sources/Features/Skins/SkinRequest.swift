#if os(macOS)
import Foundation

enum SkinsConstants {
    /// Environment variable holding the pane's UUID (set on every new surface).
    static let surfaceEnvKey = "GHOSTTY_SKINS_SURFACE"
    /// OSC 1337 SetUserVar name carrying skin requests.
    static let userVarName = "GHOSTTY_SKIN"
    static let maxPayloadBytes = 4096
}

enum SkinOp: String {
    case preview, set, cancel, reset
}

/// A request from a program in the pane (normally the `skins` CLI). It can
/// only name skins/textures and give colors and opacity, never file paths.
struct SkinRequest: Equatable {
    var op: SkinOp
    var skin: String?
    var background: RGB?
    var texture: String?
    var opacity: Double?

    /// Returns nil for anything malformed, oversized, or path-like.
    /// Unknown JSON fields are ignored for forward compatibility.
    static func decode(_ json: String) -> SkinRequest? {
        guard json.utf8.count <= SkinsConstants.maxPayloadBytes,
              let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(Raw.self, from: data),
              raw.v == 1,
              let op = SkinOp(rawValue: raw.op) else { return nil }

        var request = SkinRequest(op: op)
        if let skin = raw.skin {
            guard SkinNames.isValid(skin) else { return nil }
            request.skin = skin
        }
        if let background = raw.background {
            guard let rgb = RGB(hex: background) else { return nil }
            request.background = rgb
        }
        if let texture = raw.texture {
            guard SkinNames.isValid(texture) else { return nil }
            request.texture = texture
        }
        if let opacity = raw.opacity {
            guard (0...1).contains(opacity) else { return nil }
            request.opacity = opacity
        }
        return request
    }

    private struct Raw: Decodable {
        let v: Int
        let op: String
        let skin: String?
        let background: String?
        let texture: String?
        let opacity: Double?
    }
}
#endif
