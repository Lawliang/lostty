#if os(macOS)
import Foundation

struct RGB: Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    static let white = RGB(r: 255, g: 255, b: 255)

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parses `#rrggbb` (case-insensitive).
    init?(hex: String) {
        let digits = hex.dropFirst()
        guard hex.count == 7, hex.hasPrefix("#"), digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        r = UInt8((value >> 16) & 0xff)
        g = UInt8((value >> 8) & 0xff)
        b = UInt8(value & 0xff)
    }

    var hex: String { String(format: "#%02x%02x%02x", r, g, b) }

    /// HSL with h in degrees and s, l in 0...1.
    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> RGB {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let rgb: (Double, Double, Double) = switch hp {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        func byte(_ v: Double) -> UInt8 { UInt8((min(max(v + m, 0), 1) * 255).rounded()) }
        return RGB(r: byte(rgb.0), g: byte(rgb.1), b: byte(rgb.2))
    }

    func mixed(with other: RGB, amount t: Double) -> RGB {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded())
        }
        return RGB(r: mix(r, other.r), g: mix(g, other.g), b: mix(b, other.b))
    }
}

enum BuiltinTexture: String, CaseIterable {
    case dots, grid, diagonal, cross, waves, noise, scanlines, sparkle, rings
    case lightning, tide, blades, petals, starfield, tempest
}

enum SkinTexture: Hashable {
    case none
    case builtin(BuiltinTexture)
    case logo(path: String)
}

struct Skin: Hashable {
    var name: String
    var background: RGB
    var foreground: RGB?
    var accent: RGB
    var texture: SkinTexture
    var textureOpacity: Double
    /// Optional terminal theme (built-in presets set these).
    var accent2: RGB? = nil
    /// 16 ANSI colors, index 0–15.
    var palette: [RGB]? = nil
    var cursor: RGB? = nil
    var selectionBackground: RGB? = nil

    /// Accent used when a skin does not set one.
    static func defaultAccent(for background: RGB) -> RGB {
        background.mixed(with: .white, amount: 0.45)
    }

    /// The one accent rule for custom looks: a background or texture edit
    /// (including picking `.none`) recomputes the accent from the new
    /// background when the skin has no preset palette. A skin with a palette
    /// keeps its hand-tuned accent (and cursor/palette) untouched.
    mutating func recomputeAccentIfNeeded() {
        guard palette == nil else { return }
        accent = Skin.defaultAccent(for: background)
    }

    /// Base for color/texture overrides on a pane that has no skin.
    static let fallback = Skin(
        name: "custom",
        background: RGB(r: 0x1c, g: 0x1c, b: 0x1c),
        foreground: nil,
        accent: defaultAccent(for: RGB(r: 0x1c, g: 0x1c, b: 0x1c)),
        texture: .none,
        textureOpacity: 0.16)
}

struct SkinMatch: Hashable {
    var path: String
    var skin: String
}

enum SkinNames {
    /// Skin and texture names: 1–64 of [A-Za-z0-9_-]. Nothing path-like passes.
    static func isValid(_ s: String) -> Bool {
        (1...64).contains(s.count) && SkinsTOML.isBareKey(s)
    }
}

struct SkinConfigError: Error, Equatable, CustomStringConvertible {
    let message: String
    var description: String { message }
}

struct SkinConfig: Equatable {
    var textureOpacity: Double = 0.16
    var auto: Bool = true
    var skins: [String: Skin] = [:]
    var matches: [SkinMatch] = []

    static let empty = SkinConfig()

    /// Parses and validates skins.toml. `home` replaces a leading `~`.
    static func parse(
        _ text: String,
        home: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) throws -> SkinConfig {
        let sections: [TOMLSection]
        do {
            sections = try SkinsTOML.parse(text)
        } catch let error as TOMLError {
            throw SkinConfigError(message: error.description)
        }

        var config = SkinConfig()
        var skinSections: [(name: String, section: TOMLSection)] = []
        for section in sections {
            switch (section.path, section.isArrayElement) {
            case ([], false):
                guard section.values.isEmpty else { throw SkinConfigError(message: "skins.toml: keys must be inside a table such as [defaults] or [skins.<name>]") }
            case (["defaults"], false):
                try checkKeys(section, allowed: ["texture_opacity", "auto"])
                if let value = section.values["texture_opacity"] {
                    config.textureOpacity = try opacity(value, section)
                }
                if let value = section.values["auto"] {
                    guard case .bool(let flag) = value else { throw error(section, "auto must be true or false") }
                    config.auto = flag
                }
            case (let path, false) where path.count == 2 && path[0] == "skins":
                skinSections.append((path[1], section))
            case (["match"], true):
                try checkKeys(section, allowed: ["path", "skin"])
                guard case .string(let path)? = section.values["path"],
                      case .string(let skin)? = section.values["skin"] else {
                    throw error(section, "[[match]] needs path and skin")
                }
                config.matches.append(SkinMatch(path: expand(path, home: home), skin: skin))
            default:
                throw error(section, "unknown table [\(section.path.joined(separator: "."))]")
            }
        }

        for (name, section) in skinSections {
            config.skins[name] = try skin(
                name: name, section: section, defaultOpacity: config.textureOpacity,
                home: home, fileExists: fileExists)
        }
        let builtinNames = Set(SkinPresets.all.map(\.skin.name))
        for match in config.matches where config.skins[match.skin] == nil && !builtinNames.contains(match.skin) {
            throw SkinConfigError(message: "[[match]] \(match.path) references unknown skin '\(match.skin)'")
        }
        return config
    }

    static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst() }
        return path
    }

    private static func skin(
        name: String, section: TOMLSection, defaultOpacity: Double,
        home: String, fileExists: (String) -> Bool
    ) throws -> Skin {
        try checkKeys(section, allowed: ["background", "foreground", "accent", "logo", "texture", "texture_opacity"])
        guard SkinNames.isValid(name) else {
            throw error(section, "skin name '\(name)' may only use letters, digits, - and _")
        }
        guard let background = try color(section, "background") else {
            throw error(section, "background is required")
        }
        let foreground = try color(section, "foreground")
        let accent = try color(section, "accent")

        var texture = SkinTexture.none
        switch (section.values["logo"], section.values["texture"]) {
        case (.some, .some):
            throw error(section, "use either logo or texture, not both")
        case (.string(let logo)?, nil):
            guard accent != nil else { throw error(section, "logo requires accent") }
            let path = expand(logo, home: home)
            guard fileExists(path) else { throw error(section, "logo file not found: \(path)") }
            texture = .logo(path: path)
        case (nil, .string(let textureName)?):
            if textureName != "none" {
                guard let builtin = BuiltinTexture(rawValue: textureName) else {
                    let names = BuiltinTexture.allCases.map(\.rawValue).joined(separator: ", ")
                    throw error(section, "unknown texture '\(textureName)' (use \(names) or none)")
                }
                texture = .builtin(builtin)
            }
        case (nil, nil):
            break
        default:
            throw error(section, "logo and texture must be strings")
        }

        let textureOpacity = try section.values["texture_opacity"].map { try opacity($0, section) } ?? defaultOpacity
        return Skin(
            name: name, background: background, foreground: foreground,
            accent: accent ?? Skin.defaultAccent(for: background),
            texture: texture, textureOpacity: textureOpacity)
    }

    private static func error(_ section: TOMLSection, _ message: String) -> SkinConfigError {
        SkinConfigError(message: "skins.toml line \(section.line): \(message)")
    }

    private static func checkKeys(_ section: TOMLSection, allowed: Set<String>) throws {
        if let unknown = section.values.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw error(section, "unknown key '\(unknown)'")
        }
    }

    private static func color(_ section: TOMLSection, _ key: String) throws -> RGB? {
        guard let value = section.values[key] else { return nil }
        guard case .string(let text) = value, let rgb = RGB(hex: text) else {
            throw error(section, "\(key) must be a #rrggbb color")
        }
        return rgb
    }

    private static func opacity(_ value: TOMLValue, _ section: TOMLSection) throws -> Double {
        guard case .number(let number) = value, (0...1).contains(number) else {
            throw error(section, "texture_opacity must be a number from 0 to 1")
        }
        return number
    }
}
#endif
