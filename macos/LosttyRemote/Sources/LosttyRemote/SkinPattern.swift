import CoreGraphics
import Foundation

/// A skin's built-in texture: a pattern drawn in its accent, tiled behind
/// the terminal at the skin's texture opacity. One renderer for the Mac
/// and the phone, so a pane and its phone row match.
public enum SkinPattern: String, CaseIterable, Sendable {
    case dots, grid, diagonal, cross, waves, noise, scanlines, sparkle, rings
    case lightning, tide, blades, petals, starfield, tempest

    /// A tile's side, at `scale` 1: the Mac draws one tile pixel per device
    /// pixel.
    public static let tileSize = 220

    /// One seamless tile in `accent` on clear, `tileSize × scale` pixels
    /// square: the same drawing, `scale` times larger. nil if it can't be
    /// drawn.
    public func tile(accent: SessionSkin.RGB, scale: CGFloat = 1) -> CGImage? {
        let pixels = Int((CGFloat(Self.tileSize) * scale).rounded())
        guard pixels > 0, let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: CGFloat(pixels) / CGFloat(Self.tileSize), y: CGFloat(pixels) / CGFloat(Self.tileSize))
        draw(in: ctx, accent: accent)
        return ctx.makeImage()
    }

    private static func cgColor(_ color: SessionSkin.RGB, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                blue: CGFloat(color.b) / 255, alpha: alpha)
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func draw(in ctx: CGContext, accent: SessionSkin.RGB) {
        let size = CGFloat(Self.tileSize)
        // 8 cells per tile keeps every pattern seamless.
        let step = size / 8
        ctx.setStrokeColor(Self.cgColor(accent))
        ctx.setFillColor(Self.cgColor(accent))
        ctx.setLineWidth(1.5)
        func center(_ i: Int, _ j: Int) -> CGPoint {
            CGPoint(x: (CGFloat(i) + 0.5) * step, y: (CGFloat(j) + 0.5) * step)
        }

        switch self {
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
                ctx.setFillColor(Self.cgColor(accent, alpha: 0.3 + 0.7 * next()))
                ctx.fill(CGRect(x: next() * size, y: next() * size, width: 1.5, height: 1.5))
            }
        case .scanlines:
            // 40 lines per tile (5.5 px apart) keeps the repeat seamless.
            for i in 0..<40 {
                let y = CGFloat(i) * (size / 40) + 0.5
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: size, y: y))
            }
            ctx.setLineWidth(1)
            ctx.strokePath()
        case .sparkle:
            for i in 0..<8 {
                for j in 0..<8 {
                    let c = center(i, j)
                    ctx.fillEllipse(in: CGRect(x: c.x - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4))
                }
            }
            for i in 0..<4 {
                for j in 0..<4 {
                    let c = CGPoint(x: CGFloat(i) * size / 4 + step, y: CGFloat(j) * size / 4 + step)
                    ctx.fillEllipse(in: CGRect(x: c.x - 2.4, y: c.y - 2.4, width: 4.8, height: 4.8))
                }
            }
        case .rings:
            for i in 0..<4 {
                for j in 0..<4 {
                    let c = CGPoint(x: (CGFloat(i) + 0.5) * size / 4, y: (CGFloat(j) + 0.5) * size / 4)
                    ctx.strokeEllipse(in: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
                }
            }
        case .lightning:
            Self.addBolts(ctx)
            ctx.setLineJoin(.miter)
            ctx.setLineWidth(1.6)
            ctx.strokePath()
        case .tide:
            Self.addSwells(ctx, size: size, rows: 5, amplitude: 7)
            ctx.strokePath()
        case .blades:
            // Paired anti-diagonal cuts every 55 px (4 per tile) stay seamless.
            for k in 0...8 {
                for offset: CGFloat in [0, 5] {
                    let c = CGFloat(k) * size / 4 + offset
                    ctx.move(to: CGPoint(x: c - size, y: size))
                    ctx.addLine(to: CGPoint(x: c, y: 0))
                }
            }
            ctx.setLineWidth(1)
            ctx.strokePath()
        case .petals:
            let petals: [(x: CGFloat, y: CGFloat, angle: CGFloat)] = [
                (30, 34, 0.4), (112, 22, -0.6), (182, 58, 1.2), (66, 96, -1.1), (150, 120, 0.2),
                (24, 160, 0.9), (98, 180, -0.3), (190, 176, -1.4), (126, 64, 2.0), (54, 210, 1.6),
            ]
            for petal in petals {
                ctx.saveGState()
                ctx.translateBy(x: petal.x, y: petal.y)
                ctx.rotate(by: petal.angle)
                ctx.move(to: CGPoint(x: -7, y: 0))
                ctx.addQuadCurve(to: CGPoint(x: 7, y: 0), control: CGPoint(x: 0, y: -7))
                ctx.addQuadCurve(to: CGPoint(x: -7, y: 0), control: CGPoint(x: 0, y: 7))
                ctx.fillPath()
                ctx.restoreGState()
            }
        case .starfield:
            var seed: UInt64 = 7
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
            }
            for i in 0..<18 {
                let c = CGPoint(x: 8 + next() * (size - 16), y: 8 + next() * (size - 16))
                let arm: CGFloat = i % 3 == 0 ? 4 : 2
                ctx.move(to: CGPoint(x: c.x - arm, y: c.y))
                ctx.addLine(to: CGPoint(x: c.x + arm, y: c.y))
                ctx.move(to: CGPoint(x: c.x, y: c.y - arm))
                ctx.addLine(to: CGPoint(x: c.x, y: c.y + arm))
            }
            ctx.setLineWidth(1)
            ctx.strokePath()
            // One crescent moon per tile.
            ctx.addEllipse(in: CGRect(x: 150, y: 150, width: 34, height: 34))
            ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.addEllipse(in: CGRect(x: 160, y: 156, width: 30, height: 30))
            ctx.fillPath()
            ctx.setBlendMode(.normal)
        case .tempest:
            Self.addSwells(ctx, size: size, rows: 4, amplitude: 6)
            ctx.setLineWidth(1)
            ctx.strokePath()
            Self.addBolts(ctx)
            ctx.setLineJoin(.miter)
            ctx.setLineWidth(1.6)
            ctx.strokePath()
        }
    }

    /// Two forked bolts kept inside the tile so the repeat stays seamless.
    private static func addBolts(_ ctx: CGContext) {
        let bolt: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: -10, y: 28), CGPoint(x: 6, y: 32),
            CGPoint(x: -6, y: 64), CGPoint(x: 10, y: 68), CGPoint(x: -2, y: 96),
        ]
        for origin in [CGPoint(x: 58, y: 14), CGPoint(x: 166, y: 112)] {
            ctx.addLines(between: bolt.map { CGPoint(x: origin.x + $0.x, y: origin.y + $0.y) })
            ctx.move(to: CGPoint(x: origin.x + 6, y: origin.y + 32))
            ctx.addLine(to: CGPoint(x: origin.x + 24, y: origin.y + 46))
        }
    }

    /// Slow swells: two whole periods per row, each row phase-shifted.
    private static func addSwells(_ ctx: CGContext, size: CGFloat, rows: Int, amplitude: CGFloat) {
        for j in 0..<rows {
            let y0 = (CGFloat(j) + 0.5) * size / CGFloat(rows)
            let phase = CGFloat(j) * .pi / 2
            ctx.move(to: CGPoint(x: 0, y: y0 + amplitude * sin(phase)))
            for x in stride(from: CGFloat(2), through: size, by: 2) {
                ctx.addLine(to: CGPoint(x: x, y: y0 + amplitude * sin(x / size * 4 * .pi + phase)))
            }
        }
    }
}
