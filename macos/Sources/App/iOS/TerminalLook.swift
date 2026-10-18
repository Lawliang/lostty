#if os(iOS)
import CryptoKit
import GhosttyKit
import ImageIO
import LosttyRemote
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// How a terminal looks on the phone: its row's colors (the Mac pane's
/// skin, else the plain row's dark surface) and the size of a row's branch
/// line. Applied as a Ghostty config overlay, as the Mac applies skins.
enum TerminalLook {
    /// Ghostty draws a point as 96/72 of one on iOS; this undoes that so a
    /// size matches UIKit's.
    static let pointScale: Float32 = 72 / 96

    /// The branch line's size (`LosttyFont.mono(.footnote)`), following the
    /// phone's text size, in Ghostty's points, made smaller or larger by
    /// the chosen Text Size.
    static var fontSize: Float32 {
        Float32(UIFont.preferredFont(forTextStyle: .footnote).pointSize) * pointScale
            * TerminalTextSize.chosen.scale
    }

    /// A skin's texture at the same opacity reads stronger on the phone's
    /// small, dense screen than on the Mac's, so the phone draws it fainter.
    static func textureOpacity(_ texture: SessionSkin.Texture) -> Double {
        texture.opacity * 0.35
    }

    /// Where `apply` writes its overlays for a moment.
    static let overlayDir = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-look")

    /// `tile`: the skin's texture as a file, drawn as the Mac draws it.
    /// `fontFamily`: nil keeps Ghostty's built-in JetBrains Mono.
    static func configText(skin: SessionSkin?, fontSize: Float32, fontFamily: String? = nil, tile: URL? = nil) -> String {
        var lines = [String(format: "font-size = %.2f", fontSize)]
        if let fontFamily {
            lines.append("font-family = \"\(fontFamily)\"")
        }
        if let skin {
            lines.append("background = #\(skin.background.hexString)")
            // No text color of its own: light text, or dark on a light skin
            // (as the row does).
            lines.append("foreground = #\(skin.foreground?.hexString ?? (skin.isLight ? "1c1a1f" : "f4f1f6"))")
            lines.append("cursor-color = #\(skin.accent.hexString)")
            if let texture = skin.texture, let tile {
                lines.append("background-image = \"\(tile.path)\"")
                lines.append(String(format: "background-image-opacity = %.3f", textureOpacity(texture)))
                lines.append("background-image-fit = none")
                lines.append("background-image-position = top-left")
                lines.append("background-image-repeat = true")
            }
        } else {
            // As the row has it: LosttyTheme.surface and .textPrimary.
            lines.append("background = #17151b")
            lines.append("foreground = #f4f1f6")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The terminal's background, for what sits around it (the top bar).
    static func background(skin: SessionSkin?) -> Color {
        guard let skin else { return LosttyTheme.surface }
        return Color(red: Double(skin.background.r) / 255, green: Double(skin.background.g) / 255,
                     blue: Double(skin.background.b) / 255)
    }

    /// Text over that background: dark on a light skin.
    static func text(skin: SessionSkin?) -> Color {
        skin?.isLight == true ? Color(losttyHex: 0x1C1A1F) : LosttyTheme.textPrimary
    }

    /// The ">" before the branch, as a row has it: the skin's accent, or
    /// the text color where that accent is too pale on a light skin.
    static func prompt(skin: SessionSkin?) -> Color {
        guard let skin else { return LosttyTheme.accent }
        if skin.isLight && skin.accent.luminance > 0.4 { return text(skin: skin) }
        return Color(red: Double(skin.accent.r) / 255, green: Double(skin.accent.g) / 255,
                     blue: Double(skin.accent.b) / 255)
    }

    /// Writes the overlay and gives `surface` the config it makes, plus
    /// any `extra` lines.
    @MainActor static func apply(skin: SessionSkin?, to surface: ghostty_surface_t, overlayDir: URL, extra: [String] = []) {
        guard let cfg = ghostty_config_new() else { return }
        defer { ghostty_config_free(cfg) }
        let url = overlayDir.appendingPathComponent("\(UUID().uuidString).ghostty")
        do {
            try FileManager.default.createDirectory(at: overlayDir, withIntermediateDirectories: true)
            let tile = skin.flatMap { TextureTile.file(for: $0, displayScale: surfaceScale) }
            let text = configText(skin: skin, fontSize: fontSize, fontFamily: TerminalFontChoice.chosen.family, tile: tile) + extra.map { $0 + "\n" }.joined()
            try text.write(to: url, atomically: true, encoding: .utf8)
            ghostty_config_load_file(cfg, url.path)
            try? FileManager.default.removeItem(at: url)
        } catch {
            Ghostty.logger.warning("terminal look: couldn't write overlay: \(String(describing: error))")
        }
        ghostty_config_finalize(cfg)
        ghostty_surface_update_config(surface, cfg)
    }
}

/// Every terminal's text, a step smaller or larger than the default; picked
/// in Settings.
enum TerminalTextSize: String, CaseIterable, Identifiable {
    case smaller, standard, larger

    static let key = "LosttyTerminalTextSize"

    static var chosen: TerminalTextSize {
        UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .standard
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .smaller: "Smaller"
        case .standard: "Default"
        case .larger: "Larger"
        }
    }

    var scale: Float32 {
        switch self {
        case .smaller: 0.85
        case .standard: 1
        case .larger: 1.2
        }
    }
}

/// Every terminal's font; picked in Settings.
enum TerminalFontChoice: String, CaseIterable, Identifiable {
    case standard, hyperlegible, menlo

    static let key = "LosttyTerminalFont"

    static var chosen: TerminalFontChoice {
        UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .standard
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "JetBrains Mono"
        case .hyperlegible: "Atkinson Hyperlegible"
        case .menlo: "Menlo"
        }
    }

    /// The `font-family` to set; nil for Ghostty's built-in font.
    var family: String? {
        switch self {
        case .standard: nil
        case .hyperlegible: BundledTerminalFonts.atkinson
        case .menlo: "Menlo"
        }
    }
}

extension TerminalLook {
    /// The screen's pixels per point, which Ghostty draws images at.
    @MainActor static var surfaceScale: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen.scale }.first ?? 3
    }
}

/// A skin's texture tile on the phone: the Mac's drawing, as many points
/// across as on a Retina Mac (the Mac draws a tile pixel per device pixel).
/// Kept in memory for rows and as a file for the terminal. A pattern is
/// drawn here; a logo's tile is the Mac's, fetched (`storeLogo`).
@MainActor
enum TextureTile {
    /// A Retina Mac's pixels per point.
    static let macScale: CGFloat = 2
    private static var images: [String: CGImage] = [:]

    /// The tile at `displayScale` pixels per point; nil for a logo not
    /// fetched yet.
    static func image(for skin: SessionSkin, displayScale: CGFloat) -> CGImage? {
        guard let texture = skin.texture else { return nil }
        let key = key(texture, skin.accent, displayScale)
        if let image = images[key] { return image }
        guard case .pattern(let pattern) = texture.look else { return nil }
        let image = pattern.tile(accent: skin.accent, scale: displayScale / macScale)
        images[key] = image
        return image
    }

    /// Whether the logo tile at `tile` (on the Mac) is still to fetch.
    static func needsLogo(_ tile: String, displayScale: CGFloat) -> Bool {
        images[logoKey(tile, displayScale)] == nil
    }

    /// Keeps a logo tile the Mac drew (a PNG at its pixels), redrawn at
    /// `displayScale`. False when it isn't an image.
    static func storeLogo(_ png: Data, tile: String, displayScale: CGFloat) -> Bool {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let mac = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let pixels = Int((CGFloat(mac.width) * displayScale / macScale).rounded())
        guard pixels > 0, let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.interpolationQuality = .high
        ctx.draw(mac, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let image = ctx.makeImage() else { return false }
        images[logoKey(tile, displayScale)] = image
        return true
    }

    /// The tile as a PNG in the app's caches, for Ghostty's background image.
    static func file(for skin: SessionSkin, displayScale: CGFloat) -> URL? {
        guard let texture = skin.texture,
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = caches.appendingPathComponent("textures/v1-\(key(texture, skin.accent, displayScale)).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let image = image(for: skin, displayScale: displayScale) else { return nil }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(out, image, nil)
            return CGImageDestinationFinalize(out) ? url : nil
        } catch {
            Ghostty.logger.warning("terminal look: couldn't write texture: \(String(describing: error))")
            return nil
        }
    }

    private static func key(_ texture: SessionSkin.Texture, _ accent: SessionSkin.RGB, _ scale: CGFloat) -> String {
        switch texture.look {
        case .pattern(let pattern): "\(pattern.rawValue)-\(accent.hexString)-\(Int(scale * 100))"
        case .logo(let tile): logoKey(tile, scale)
        }
    }

    /// The Mac names a logo's tile after its picture, its date and the
    /// accent, so its path tells one apart.
    private static func logoKey(_ tile: String, _ scale: CGFloat) -> String {
        let digest = SHA256.hash(data: Data(tile.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "logo-\(digest)-\(Int(scale * 100))"
    }
}

private extension SessionSkin.RGB {
    var hexString: String { String(format: "%02x%02x%02x", r, g, b) }
}
#endif
