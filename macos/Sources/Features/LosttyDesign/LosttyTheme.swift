import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Lostty's look: dark and calm, magenta as the one accent. Shared by the
/// iPhone app and the Mac's Phone Access window.
enum LosttyTheme {
    static let background = Color(losttyHex: 0x0C0B0E)
    static let surface = Color(losttyHex: 0x17151B)
    static let surfaceRaised = Color(losttyHex: 0x211E26)
    static let hairline = Color(losttyHex: 0x2C2833)
    static let textPrimary = Color(losttyHex: 0xF4F1F6)
    static let textSecondary = Color(losttyHex: 0xA39CAA)
    /// Sampled from the app icon's face.
    static let accent = Color(losttyHex: 0xE5199C)
    static let accentSoft = accent.opacity(0.16)
    static let success = Color(losttyHex: 0x3FB27F)
    static let warning = Color(losttyHex: 0xE0A23A)
    static let danger = Color(losttyHex: 0xE5484D)

    static let radius: CGFloat = 16
    static let margin: CGFloat = 16
    static let gap: CGFloat = 12
    static let motion = Animation.easeInOut(duration: 0.2)
}

/// Text styles: Dynamic Type on iPhone, the same sizes fixed on the Mac.
enum LosttyFont {
    #if os(iOS)
    static let largeTitle = Font.system(.title, weight: .semibold)
    static let title = Font.system(.title3, weight: .semibold)
    static let body = Font.system(.callout)
    static let bodyEmphasis = Font.system(.callout, weight: .semibold)
    static let detail = Font.system(.footnote)
    static let button = Font.system(.headline)
    static func mono(_ style: Font.TextStyle = .callout, size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
    #else
    static let largeTitle = Font.system(size: 28, weight: .semibold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 16)
    static let bodyEmphasis = Font.system(size: 16, weight: .semibold)
    static let detail = Font.system(size: 13)
    static let button = Font.system(size: 17, weight: .semibold)
    static func mono(_ style: Font.TextStyle = .callout, size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    #endif
}

extension Color {
    /// 0xRRGGBB in sRGB.
    init(losttyHex hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

#if os(iOS)
/// The tokens UIKit views need (the key row).
enum LosttyUIColor {
    static let background = UIColor(LosttyTheme.background)
    static let surfaceRaised = UIColor(LosttyTheme.surfaceRaised)
    static let textPrimary = UIColor(LosttyTheme.textPrimary)
    static let accent = UIColor(LosttyTheme.accent)
}
#endif
