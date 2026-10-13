import Foundation

/// An sRGB color, 8 bits a channel. Skins are made of these; the phone
/// draws Claude's trace with them too.
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
