#if os(macOS)
import SwiftUI

/// The boon picker's gilded look: bronze/gold metalwork, rarity colors,
/// hex-ended bars and patron emblems.
enum Boon {
    static let ground = Color(red: 13 / 255, green: 10 / 255, blue: 11 / 255)
    static let rowFill = Color(red: 18 / 255, green: 14 / 255, blue: 11 / 255)
    static let goldLight = Color(red: 1, green: 241 / 255, blue: 196 / 255)
    static let gold = Color(red: 227 / 255, green: 184 / 255, blue: 90 / 255)
    static let goldDark = Color(red: 154 / 255, green: 106 / 255, blue: 38 / 255)
    static let bronze = Color(red: 92 / 255, green: 69 / 255, blue: 33 / 255)
    static let bronzeDark = Color(red: 59 / 255, green: 43 / 255, blue: 21 / 255)
    static let parchment = Color(red: 233 / 255, green: 225 / 255, blue: 207 / 255)
    static let faded = Color(red: 169 / 255, green: 154 / 255, blue: 124 / 255)
    static let ink = Color(red: 28 / 255, green: 18 / 255, blue: 8 / 255)

    static let goldFill = LinearGradient(colors: [goldLight, gold, goldDark], startPoint: .top, endPoint: .bottom)
    static let goldRim = LinearGradient(colors: [goldLight, gold, goldDark], startPoint: .leading, endPoint: .trailing)
    static let bronzeRim = LinearGradient(colors: [bronze, bronzeDark], startPoint: .leading, endPoint: .trailing)

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension SkinRarity {
    var label: String { rawValue.uppercased() }

    var color: Color {
        switch self {
        case .legendary: Color(red: 1, green: 166 / 255, blue: 48 / 255)
        case .heroic: Color(red: 1, green: 90 / 255, blue: 82 / 255)
        case .epic: Color(red: 185 / 255, green: 123 / 255, blue: 1)
        case .rare: Color(red: 79 / 255, green: 163 / 255, blue: 1)
        case .common: Color(red: 217 / 255, green: 212 / 255, blue: 199 / 255)
        case .duo: Color(red: 184 / 255, green: 243 / 255, blue: 90 / 255)
        case .project: Boon.gold
        }
    }
}

/// A bar with pointed ends, like the boon choices it is modeled on.
struct HexBar: InsettableShape {
    var notch: CGFloat = 14
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let n = min(notch, r.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + n, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - n, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        path.addLine(to: CGPoint(x: r.maxX - n, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + n, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.midY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> HexBar {
        var bar = self
        bar.inset += amount
        return bar
    }
}

/// A patron emblem drawn on a 24-point grid and scaled to fit.
struct SkinGlyphShape: Shape {
    let glyph: SkinGlyph

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        switch glyph {
        case .bolt:
            p.addLines([pt(13, 2), pt(4, 14), pt(11, 14), pt(9, 22), pt(20, 9), pt(13, 9)])
            p.closeSubpath()
        case .trident:
            p.move(to: pt(12, 2)); p.addLine(to: pt(12, 22))
            p.move(to: pt(6, 3)); p.addLine(to: pt(6, 7))
            p.addQuadCurve(to: pt(12, 11), control: pt(6, 11))
            p.addQuadCurve(to: pt(18, 7), control: pt(18, 11))
            p.addLine(to: pt(18, 3))
            for x: CGFloat in [6, 12, 18] {
                p.move(to: pt(x - 1.5, x == 12 ? 4 : 5)); p.addLine(to: pt(x, x == 12 ? 2 : 3))
                p.addLine(to: pt(x + 1.5, x == 12 ? 4 : 5))
            }
        case .sword:
            p.move(to: pt(20, 4)); p.addLine(to: pt(9, 15))
            p.move(to: pt(15, 4)); p.addLine(to: pt(20, 4)); p.addLine(to: pt(20, 9))
            p.move(to: pt(7, 13)); p.addLine(to: pt(11, 17))
            p.move(to: pt(8, 16)); p.addLine(to: pt(4, 20))
        case .heart:
            p.move(to: pt(12, 20))
            p.addCurve(to: pt(4, 9.8), control1: pt(6, 16.4), control2: pt(4, 12.6))
            p.addCurve(to: pt(12, 8.4), control1: pt(4, 6.2), control2: pt(9.6, 4.8))
            p.addCurve(to: pt(20, 9.8), control1: pt(14.4, 4.8), control2: pt(20, 6.2))
            p.addCurve(to: pt(12, 20), control1: pt(20, 12.6), control2: pt(18, 16.4))
            p.closeSubpath()
        case .moon:
            p.move(to: pt(16.5, 4.2))
            p.addCurve(to: pt(3.5, 14), control1: pt(8, 2), control2: pt(2, 8))
            p.addCurve(to: pt(16.5, 19.8), control1: pt(5, 20), control2: pt(12, 23))
            p.addCurve(to: pt(16.5, 4.2), control1: pt(11, 17), control2: pt(10, 8))
            p.closeSubpath()
        case .stormsea:
            p.addLines([pt(13, 2), pt(8, 10), pt(12, 10), pt(10.5, 15), pt(16.5, 7), pt(12.5, 7)])
            p.closeSubpath()
            p.move(to: pt(2, 20))
            var x: CGFloat = 2
            var up = true
            while x < 20 {
                p.addQuadCurve(to: pt(x + 4.5, 20), control: pt(x + 2.25, up ? 17.5 : 22.5))
                x += 4.5
                up.toggle()
            }
        case .spark:
            p.move(to: pt(12, 2))
            p.addQuadCurve(to: pt(22, 12), control: pt(13, 11))
            p.addQuadCurve(to: pt(12, 22), control: pt(13, 13))
            p.addQuadCurve(to: pt(2, 12), control: pt(11, 13))
            p.addQuadCurve(to: pt(12, 2), control: pt(11, 11))
            p.closeSubpath()
        case .sigil:
            p.addLines([pt(12, 3), pt(21, 12), pt(12, 21), pt(3, 12)])
            p.closeSubpath()
            p.addLines([pt(12, 8), pt(16, 12), pt(12, 16), pt(8, 12)])
            p.closeSubpath()
        }
        let scale = min(rect.width, rect.height) / 24
        let dx = rect.midX - 12 * scale
        let dy = rect.midY - 12 * scale
        return p.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: dx, ty: dy))
    }
}

/// The diamond frame a boon's emblem sits in: rarity-colored rim around
/// the skin's own ground and texture.
struct BoonEmblem: View {
    let skin: Skin
    let rarity: SkinRarity
    let glyph: SkinGlyph
    var texture: CGImage?
    var size: CGFloat = 44

    var body: some View {
        let side = size / 1.414
        ZStack {
            ZStack {
                Rectangle().fill(Color(rgb: skin.background))
                if let texture {
                    Image(decorative: texture, scale: 2).resizable(resizingMode: .tile).opacity(0.5)
                }
                RadialGradient(colors: [Color(rgb: skin.accent).opacity(0.35), .clear],
                               center: .center, startRadius: 0, endRadius: side / 1.2)
            }
            .frame(width: side, height: side)
            .clipped()
            .overlay(Rectangle().strokeBorder(rarity.color, lineWidth: 1.5))
            .padding(2)
            .overlay(Rectangle().strokeBorder(Boon.bronze, lineWidth: 1))
            .rotationEffect(.degrees(45))
            SkinGlyphShape(glyph: glyph)
                .stroke(Color(rgb: skin.accent), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.46, height: size * 0.46)
                .shadow(color: Color(rgb: skin.accent).opacity(0.8), radius: 4)
        }
        .frame(width: size, height: size)
    }
}

/// A short gold rule with a diamond in the middle.
struct BoonDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            LinearGradient(colors: [.clear, Boon.goldDark], startPoint: .leading, endPoint: .trailing).frame(height: 1)
            Rectangle().fill(Boon.gold).frame(width: 6, height: 6).rotationEffect(.degrees(45))
            LinearGradient(colors: [Boon.goldDark, .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1)
        }
    }
}
#endif
