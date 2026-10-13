import CoreGraphics
import Testing
@testable import LosttyRemote

struct SkinPatternTests {
    let accent = SessionSkin.RGB(r: 0xe5, g: 0x19, b: 0x9c)

    @Test func everyPatternDrawsATileWithSomethingOnIt() throws {
        for pattern in SkinPattern.allCases {
            let tile = try #require(pattern.tile(accent: accent), "\(pattern)")
            #expect(tile.width == SkinPattern.tileSize && tile.height == SkinPattern.tileSize, "\(pattern)")
            #expect(Self.coverage(tile) > 0, "\(pattern)")
        }
    }

    @Test func aScaledTileIsTheSameDrawingLarger() throws {
        let tile = try #require(SkinPattern.dots.tile(accent: accent, scale: 1.5))
        #expect(tile.width == 330 && tile.height == 330)
        // About as much of it is covered either way.
        let small = Self.coverage(try #require(SkinPattern.dots.tile(accent: accent)))
        #expect(abs(Self.coverage(tile) - small) < 0.02)
    }

    /// The share of pixels with anything drawn on them.
    static func coverage(_ image: CGImage) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let drawn = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
        return Double(drawn) / Double(width * height)
    }
}
