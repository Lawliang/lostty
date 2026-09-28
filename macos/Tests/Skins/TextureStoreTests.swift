#if os(macOS)
import AppKit
import Foundation
import ImageIO
import Testing
@testable import Ghostty

struct TextureStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("skins-tex-\(UUID().uuidString)")
    }

    private func skin(_ texture: SkinTexture, accent: String = "#46a2ff") -> Skin {
        Skin(name: "t", background: RGB(hex: "#12222b")!, foreground: nil,
             accent: RGB(hex: accent)!, texture: texture, textureOpacity: 0.16)
    }

    private func loadImage(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Pixels with any alpha. Counted directly (not via `logoMask`), because a
    /// tile whose top-left pixel is painted would otherwise look "opaque".
    private func paintedPixels(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
    }

    @Test func noneHasNoTile() throws {
        #expect(try TextureStore(cacheDir: tempDir()).tileURL(for: skin(.none)) == nil)
    }

    @Test(arguments: BuiltinTexture.allCases)
    func builtinTilesRender(_ texture: BuiltinTexture) throws {
        let url = try #require(try TextureStore(cacheDir: tempDir()).tileURL(for: skin(.builtin(texture))))
        let image = try loadImage(url)
        #expect(image.width == TextureStore.tileSize)
        #expect(image.height == TextureStore.tileSize)
        #expect(paintedPixels(image) > 100)
    }

    @Test func tilesAreCachedPerAccent() throws {
        let store = TextureStore(cacheDir: tempDir())
        let first = try store.tileURL(for: skin(.builtin(.grid)))
        let modified = try FileManager.default.attributesOfItem(atPath: first!.path)[.modificationDate] as? Date
        let again = try store.tileURL(for: skin(.builtin(.grid)))
        #expect(first == again)
        #expect(try FileManager.default.attributesOfItem(atPath: again!.path)[.modificationDate] as? Date == modified)
        #expect(try store.tileURL(for: skin(.builtin(.grid), accent: "#ff0000")) != first)
    }

    @Test func maskIgnoresAnOpaqueBackground() throws {
        let ctx = try TextureStore.makeContext(width: 64, height: 64)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 24, y: 24, width: 16, height: 16))
        let mask = TextureStore.logoMask(try #require(ctx.makeImage()))
        #expect(mask[0] == 0)
        #expect(mask[32 * 64 + 32] == 255)
    }

    @Test func maskUsesAlphaForTransparentLogos() throws {
        let ctx = try TextureStore.makeContext(width: 64, height: 64)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 24, y: 24, width: 16, height: 16))
        let mask = TextureStore.logoMask(try #require(ctx.makeImage()))
        #expect(mask[0] == 0)
        #expect(mask[32 * 64 + 32] == 255)
    }

    @Test func maskIgnoresARoundedOpaqueBackground() throws {
        let ctx = try TextureStore.makeContext(width: 64, height: 64)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 64, height: 64),
                            cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 24, y: 24, width: 16, height: 16))
        let mask = TextureStore.logoMask(try #require(ctx.makeImage()))
        #expect(mask[0] == 0)
        #expect(mask[10 * 64 + 32] == 0)
        #expect(mask[32 * 64 + 32] == 255)
    }

    @Test func maskFallsBackToAlphaWithoutADominantBackground() throws {
        let ctx = try TextureStore.makeContext(width: 64, height: 64)
        for column in 0..<64 {
            let level = CGFloat(column * 4) / 255
            ctx.setFillColor(CGColor(red: level, green: level, blue: level, alpha: 1))
            ctx.fill(CGRect(x: CGFloat(column), y: 0, width: 1, height: 64))
        }
        let mask = TextureStore.logoMask(try #require(ctx.makeImage()))
        #expect(mask.allSatisfy { $0 == 255 })
    }

    @Test func svgLogoTileRenders() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let svg = dir.appendingPathComponent("logo.svg")
        try ##"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><rect width="32" height="32" fill="#ffffff"/><circle cx="16" cy="16" r="8" fill="none" stroke="#12222b" stroke-width="3"/></svg>"##
            .write(to: svg, atomically: true, encoding: .utf8)
        let url = try #require(try TextureStore(cacheDir: dir.appendingPathComponent("cache"))
            .tileURL(for: skin(.logo(path: svg.path))))
        let image = try loadImage(url)
        let painted = paintedPixels(image)
        #expect(painted > 50)
        // The white square background must not be tinted (it would paint ~2*57*57 pixels).
        #expect(painted < 2 * 57 * 57 / 2)
    }

    @Test func unreadableLogoThrows() {
        #expect(throws: TextureError.self) {
            try TextureStore(cacheDir: tempDir()).tileURL(for: skin(.logo(path: "/nonexistent/logo.svg")))
        }
    }
}
#endif
