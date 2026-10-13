import Foundation

/// A session's look on the Mac (its pane's skin), as the phone draws its
/// row. The Mac keeps it in tmux (`@lostty_skin`) as
/// "background,foreground,accent" in hex, the foreground empty when the
/// skin leaves it to the terminal.
public struct SessionSkin: Equatable, Sendable {
    public struct RGB: Equatable, Sendable {
        public var r: UInt8
        public var g: UInt8
        public var b: UInt8

        public init(r: UInt8, g: UInt8, b: UInt8) {
            self.r = r
            self.g = g
            self.b = b
        }

        /// "1c1c1c" (no "#": tmux would read one as a format).
        init?(hex: Substring) {
            guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else { return nil }
            r = UInt8((value >> 16) & 0xff)
            g = UInt8((value >> 8) & 0xff)
            b = UInt8(value & 0xff)
        }

        var hex: String { String(format: "%02x%02x%02x", r, g, b) }

        /// Relative luminance, 0 (black) to 1 (white).
        public var luminance: Double {
            func linear(_ c: UInt8) -> Double {
                let v = Double(c) / 255
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
    }

    /// A texture, tiled over the background in the accent.
    public struct Texture: Equatable, Sendable {
        public enum Look: Equatable, Sendable {
            /// A built-in pattern, which the phone draws itself.
            case pattern(SkinPattern)
            /// A logo: the tile the Mac drew of it, a PNG at this path on
            /// the Mac (its 220 pixels square), for the phone to fetch.
            case logo(tile: String)
        }

        public var look: Look
        /// How strongly it shows, 0 to 1, to three places (as it's sent).
        public var opacity: Double

        public init(look: Look, opacity: Double) {
            self.look = look
            self.opacity = (min(max(opacity, 0), 1) * 1000).rounded() / 1000
        }

        public init(pattern: SkinPattern, opacity: Double) {
            self.init(look: .pattern(pattern), opacity: opacity)
        }
    }

    /// A tile path as sent: no commas (they separate the fields).
    private static let tileAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: ",%"))

    public var background: RGB
    public var foreground: RGB?
    public var accent: RGB
    public var texture: Texture?

    public init(background: RGB, foreground: RGB?, accent: RGB, texture: Texture? = nil) {
        self.background = background
        self.foreground = foreground
        self.accent = accent
        self.texture = texture
    }

    /// "1c1c1c,e0e0e0,89b4fa", then ",waves,0.160" with a pattern, or
    /// ",logo,0.160,<tile path, percent-encoded>" with a logo; nil when it
    /// isn't one. A texture this phone doesn't know (from a newer Mac) is
    /// left off, not the skin.
    public init?(encoded: String) {
        let parts = encoded.split(separator: ",", omittingEmptySubsequences: false)
        guard (3...6).contains(parts.count), parts.count != 4,
              let background = RGB(hex: parts[0]), let accent = RGB(hex: parts[2]) else { return nil }
        let foreground = RGB(hex: parts[1])
        guard foreground != nil || parts[1].isEmpty else { return nil }
        var texture: Texture?
        if parts.count >= 5, let opacity = Double(parts[4]) {
            if parts.count == 5, let pattern = SkinPattern(rawValue: String(parts[3])) {
                texture = Texture(pattern: pattern, opacity: opacity)
            } else if parts.count == 6, parts[3] == "logo", let tile = parts[5].removingPercentEncoding, !tile.isEmpty {
                texture = Texture(look: .logo(tile: tile), opacity: opacity)
            }
        }
        self.init(background: background, foreground: foreground, accent: accent, texture: texture)
    }

    public var encoded: String {
        var parts = [background.hex, foreground?.hex ?? "", accent.hex]
        if let texture {
            let opacity = String(format: "%.3f", texture.opacity)
            switch texture.look {
            case .pattern(let pattern):
                parts += [pattern.rawValue, opacity]
            case .logo(let tile):
                parts += ["logo", opacity, tile.addingPercentEncoding(withAllowedCharacters: Self.tileAllowed) ?? ""]
            }
        }
        return parts.joined(separator: ",")
    }

    /// A light background wants dark text.
    public var isLight: Bool { background.luminance > 0.4 }
}
