#if os(macOS)
import AppKit
import Foundation
import ImageIO

enum TextureError: Error, Equatable {
    case render(String)
    case unreadableLogo(String)
}

/// Renders and caches 220×220 device-pixel tiles. Ghostty draws
/// `background-image-fit = none` at one image pixel per device pixel.
final class TextureStore {
    static let tileSize = 220
    static let logoSize = 57
    /// Staggered logo placement within a tile (matches the spike's look).
    static let logoOrigins = [CGPoint(x: 30, y: 30), CGPoint(x: 140, y: 135)]

    let cacheDir: URL

    init(cacheDir: URL) {
        self.cacheDir = cacheDir
    }

    func tileURL(for skin: Skin) throws -> URL? {
        let key: String
        let render: () throws -> CGImage
        switch skin.texture {
        case .none:
            return nil
        case .builtin(let texture):
            key = "b-\(texture.rawValue)-\(skin.accent.hex.dropFirst())"
            render = { try Self.renderBuiltin(texture, accent: skin.accent) }
        case .logo(let path):
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
                throw TextureError.unreadableLogo(path)
            }
            let mtime = Int((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
            key = "l-\(String(AutoSkin.fnv1a(path), radix: 16))-\(mtime)-\(skin.accent.hex.dropFirst())"
            render = { try Self.renderLogoTile(path: path, accent: skin.accent) }
        }

        let url = cacheDir.appendingPathComponent("v1-\(key).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let image = try render()
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Self.writePNG(image, to: url)
        return url
    }

    static func makeContext(width: Int, height: Int) throws -> CGContext {
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw TextureError.render("could not create bitmap context")
        }
        return ctx
    }

    static func cgColor(_ color: RGB, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                blue: CGFloat(color.b) / 255, alpha: alpha)
    }

    static func renderBuiltin(_ texture: BuiltinTexture, accent: RGB) throws -> CGImage {
        let size = CGFloat(tileSize)
        let ctx = try makeContext(width: tileSize, height: tileSize)
        // 8 cells per tile keeps every pattern seamless.
        let step = size / 8
        ctx.setStrokeColor(cgColor(accent))
        ctx.setFillColor(cgColor(accent))
        ctx.setLineWidth(1.5)
        func center(_ i: Int, _ j: Int) -> CGPoint {
            CGPoint(x: (CGFloat(i) + 0.5) * step, y: (CGFloat(j) + 0.5) * step)
        }

        switch texture {
        case .dots:
            for i in 0..<8 {
                for j in 0..<8 {
                    let c = center(i, j)
                    ctx.fillEllipse(in: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5))
                }
            }
        case .grid:
            for i in 0..<8 {
                let p = CGFloat(i) * step + 0.75
                ctx.move(to: CGPoint(x: p, y: 0))
                ctx.addLine(to: CGPoint(x: p, y: size))
                ctx.move(to: CGPoint(x: 0, y: p))
                ctx.addLine(to: CGPoint(x: size, y: p))
            }
            ctx.strokePath()
        case .diagonal:
            for k in -8...8 {
                let offset = CGFloat(k) * step
                ctx.move(to: CGPoint(x: offset, y: 0))
                ctx.addLine(to: CGPoint(x: offset + size, y: size))
            }
            ctx.strokePath()
        case .cross:
            for i in 0..<8 {
                for j in 0..<8 {
                    let c = center(i, j)
                    ctx.move(to: CGPoint(x: c.x - 4, y: c.y))
                    ctx.addLine(to: CGPoint(x: c.x + 4, y: c.y))
                    ctx.move(to: CGPoint(x: c.x, y: c.y - 4))
                    ctx.addLine(to: CGPoint(x: c.x, y: c.y + 4))
                }
            }
            ctx.strokePath()
        case .waves:
            for j in 0..<8 {
                let y0 = (CGFloat(j) + 0.5) * step
                ctx.move(to: CGPoint(x: 0, y: y0))
                for x in stride(from: CGFloat(0), through: size, by: 2) {
                    ctx.addLine(to: CGPoint(x: x, y: y0 + 4 * sin(x / size * 8 * .pi)))
                }
            }
            ctx.strokePath()
        case .noise:
            var seed: UInt64 = 42
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
            }
            for _ in 0..<700 {
                ctx.setFillColor(cgColor(accent, alpha: 0.3 + 0.7 * next()))
                ctx.fill(CGRect(x: next() * size, y: next() * size, width: 1.5, height: 1.5))
            }
        }

        guard let image = ctx.makeImage() else { throw TextureError.render("makeImage failed") }
        return image
    }

    static func renderLogoTile(path: String, accent: RGB) throws -> CGImage {
        guard let logo = NSImage(contentsOfFile: path), logo.size.width > 0, logo.size.height > 0 else {
            throw TextureError.unreadableLogo(path)
        }
        let n = logoSize
        let logoCtx = try makeContext(width: n, height: n)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: logoCtx, flipped: false)
        logo.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
        NSGraphicsContext.restoreGraphicsState()
        guard let logoImage = logoCtx.makeImage() else { throw TextureError.render("logo render failed") }

        let tinted = try tintedImage(mask: logoMask(logoImage), width: n, height: n, color: accent)
        let tile = try makeContext(width: tileSize, height: tileSize)
        for origin in logoOrigins {
            tile.draw(tinted, in: CGRect(origin: origin, size: CGSize(width: n, height: n)))
        }
        guard let image = tile.makeImage() else { throw TextureError.render("tile render failed") }
        return image
    }

    /// Row-major alpha mask (0–255) of the logo's shape. If the image has an
    /// opaque background (the image's most common pixel value has alpha ≥
    /// 230), the shape is the pixels whose color differs from that background;
    /// otherwise it is the alpha channel.
    ///
    /// The background is found by a majority vote over every pixel rather
    /// than by sampling the top-left corner: a logo whose background has
    /// rounded corners (e.g. `rect rx="7"`) has a *transparent* corner pixel
    /// even though the bulk of the image is an opaque fill, which would
    /// otherwise misdetect the background as transparent and let the alpha
    /// channel (opaque for both fill and strokes) paint the whole shape solid.
    static func logoMask(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var counts: [UInt32: Int] = [:]
        for i in 0..<(width * height) {
            let key = UInt32(pixels[i * 4]) << 24 | UInt32(pixels[i * 4 + 1]) << 16
                | UInt32(pixels[i * 4 + 2]) << 8 | UInt32(pixels[i * 4 + 3])
            counts[key, default: 0] += 1
        }
        let backgroundKey = counts.max { $0.value < $1.value }?.key ?? 0
        let background: [UInt8] = [
            UInt8((backgroundKey >> 24) & 0xff), UInt8((backgroundKey >> 16) & 0xff),
            UInt8((backgroundKey >> 8) & 0xff),
        ]
        let opaqueBackground = UInt8(backgroundKey & 0xff) >= 230

        var mask = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let alpha = pixels[i * 4 + 3]
            guard opaqueBackground else {
                mask[i] = alpha
                continue
            }
            let difference = (0..<3).map { abs(Int(pixels[i * 4 + $0]) - Int(background[$0])) }.max() ?? 0
            let strength = min(1, Double(difference) / 255 / 0.35)
            mask[i] = UInt8((strength * Double(alpha)).rounded())
        }
        return mask
    }

    private static func tintedImage(mask: [UInt8], width: Int, height: Int, color: RGB) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let alpha = UInt16(mask[i])
            pixels[i * 4] = UInt8(UInt16(color.r) * alpha / 255)
            pixels[i * 4 + 1] = UInt8(UInt16(color.g) * alpha / 255)
            pixels[i * 4 + 2] = UInt8(UInt16(color.b) * alpha / 255)
            pixels[i * 4 + 3] = mask[i]
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw TextureError.render("tint failed")
        }
        return image
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw TextureError.render("could not create \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TextureError.render("could not write \(url.path)")
        }
    }
}
#endif
