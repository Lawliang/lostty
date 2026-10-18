import CoreText
import Foundation

/// Fonts Lostty ships for its terminals, on the Mac and the phone.
/// Registered for this process at launch, so Ghostty's font search finds
/// them by family name (`font-family = "Atkinson Hyperlegible Mono"`) as if
/// they were installed.
enum BundledTerminalFonts {
    /// Atkinson Hyperlegible Mono, the Braille Institute's typeface drawn to
    /// keep look-alike characters (0/O, 1/l/I) apart. SIL Open Font License
    /// (Fonts/AtkinsonHyperlegibleMono-OFL.txt).
    static let atkinson = "Atkinson Hyperlegible Mono"

    /// Geist Mono, Vercel's monospaced companion to Geist: the clean,
    /// Inter-like look, with every character the same width. SIL Open Font
    /// License (Fonts/GeistMono-OFL.txt).
    static let geist = "Geist Mono"

    static let families = [atkinson, geist]

    private static let files = [
        "AtkinsonHyperlegibleMono-Regular", "AtkinsonHyperlegibleMono-Bold",
        "AtkinsonHyperlegibleMono-Italic", "AtkinsonHyperlegibleMono-BoldItalic",
        "GeistMono-Regular", "GeistMono-Bold", "GeistMono-Italic", "GeistMono-BoldItalic",
    ]

    /// Call before the first terminal opens.
    static func register(bundle: Bundle = .main) {
        let urls = files.compactMap { bundle.url(forResource: $0, withExtension: "ttf") }
        if urls.count != files.count {
            NSLog("lostty: bundled terminal fonts: \(files.count - urls.count) missing from the app")
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
