#if os(macOS)
import AppKit
import SwiftUI

/// JetBrains Mono, the redesign's one font, in the weights it uses.
enum PaneFont {
    private static let registered: Bool = {
        _ = ClaudeUsageFont.font(size: 12)
        for name in ["JetBrainsMono-Medium", "JetBrainsMono-Bold"] where NSFont(name: name, size: 12) == nil {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        return true
    }()

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        _ = registered
        let name = switch weight {
        case .bold, .heavy, .black, .semibold: "JetBrainsMono-Bold"
        case .medium: "JetBrainsMono-Medium"
        default: "JetBrainsMono-Regular"
        }
        return NSFont(name: name, size: size) == nil
            ? .system(size: size, weight: weight, design: .monospaced) : .custom(name, size: size)
    }
}
#endif
