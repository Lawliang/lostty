#if os(macOS)
import AppKit
import GhosttyKit

/// Lostty's two window styles. Classic: the title and bottom bars take
/// the panes' color. Mockup, the canvas drag-select mockup's: a terminal
/// with no skin is its dark purple-gray, the bars are a step lighter than
/// the panes with a hairline between, and a card's title is centered over
/// a faint edge and a long soft shadow. View → Mockup Window Style switches
/// between them.
enum LosttyWindowStyle {
    static let key = "LosttyMockupWindowStyle"

    /// Read from any thread (a config reload).
    static var isMockup: Bool { UserDefaults.ghostty.bool(forKey: key) }

    /// The mockup's terminal, title bar and text.
    static let mockupBackground = RGB(r: 0x1B, g: 0x18, b: 0x20)
    static let mockupBar = RGB(r: 0x2C, g: 0x28, b: 0x32)
    static let mockupText = RGB(r: 0xA4, g: 0x9D, b: 0xAE)

    /// A card's title bar and bottom bar: the mockup's 28pt, or a standard
    /// title bar's.
    static var barHeight: CGFloat {
        isMockup ? 28 : NSWindow.frameRect(forContentRect: .zero, styleMask: [.titled]).height
    }

    /// The title and bottom bars' color over panes of `background`: the
    /// mockup's own over its terminal, else as much lighter (darker over a
    /// light pane).
    static func bar(over background: NSColor) -> NSColor {
        guard isMockup, let rgb = background.usingColorSpace(.sRGB) else { return background }
        let alpha = background.alphaComponent
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        if components.map({ UInt8(($0 * 255).rounded()) }) == [mockupBackground.r, mockupBackground.g, mockupBackground.b] {
            return nsColor(mockupBar).withAlphaComponent(alpha)
        }
        let toward: CGFloat = background.isLightColor ? 0 : 1
        let mixed = components.map { $0 + (toward - $0) * 0.075 }
        return NSColor(srgbRed: mixed[0], green: mixed[1], blue: mixed[2], alpha: alpha)
    }

    /// The line under a title bar and over a bottom bar of `bar`.
    static func hairline(on bar: NSColor) -> NSColor {
        (bar.isLightColor ? NSColor.black : NSColor.white).withAlphaComponent(0.1)
    }

    /// A title over panes showing `skin`, in the terminal's text color as
    /// the mockup's is.
    static func titleColor(skin: Skin?, bar: NSColor) -> NSColor {
        if let foreground = skin?.foreground { return nsColor(foreground) }
        return bar.isLightColor ? NSColor(white: 0.2, alpha: 1) : nsColor(mockupText)
    }

    static func nsColor(_ rgb: RGB) -> NSColor {
        NSColor(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255, alpha: 1)
    }

    /// Loads the mockup's colors before the user's config, so the config
    /// and skins still win over them.
    static func loadBaseConfig(_ cfg: ghostty_config_t) {
        guard isMockup else { return }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/window-style/mockup.ghostty")
        if (try? String(contentsOf: url, encoding: .utf8)) != mockupColors {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? mockupColors.write(to: url, atomically: true, encoding: .utf8)
        }
        ghostty_config_load_file(cfg, url.path)
    }

    /// The mockup's terminal: its text and background, and the green, blue,
    /// magenta and dim it shows, with the other ANSI colors in the same tone.
    private static let mockupColors = """
        background = #1B1820
        foreground = #A49DAE
        cursor-color = #D9D3E2
        selection-background = #3A3444
        palette = 0=#2C2832
        palette = 1=#E8737E
        palette = 2=#5FCB8A
        palette = 3=#E0B55A
        palette = 4=#6FA8FF
        palette = 5=#D58AD0
        palette = 6=#5CC6C9
        palette = 7=#A49DAE
        palette = 8=#6E6878
        palette = 9=#F29AA2
        palette = 10=#8ADBA9
        palette = 11=#ECCB85
        palette = 12=#9DC3FF
        palette = 13=#E3ADDF
        palette = 14=#8AD8DA
        palette = 15=#F1EEF5

        """
}

/// View → Mockup Window Style.
@MainActor
final class WindowStylePreferences: ObservableObject {
    static let shared = WindowStylePreferences()

    @Published var isMockup = LosttyWindowStyle.isMockup {
        didSet {
            guard isMockup != oldValue else { return }
            UserDefaults.ghostty.set(isMockup, forKey: LosttyWindowStyle.key)
            (NSApp.delegate as? AppDelegate)?.ghostty.reloadConfig()
        }
    }

    static func installMenuItem(before anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Mockup Window Style", action: #selector(MenuTarget.toggle(_:)), keyEquivalent: "")
        item.target = MenuTarget.shared
        let index = menu.index(of: anchor)
        menu.insertItem(item, at: index)
        menu.insertItem(.separator(), at: index + 1)
    }

    @MainActor
    final class MenuTarget: NSObject, NSMenuItemValidation {
        static let shared = MenuTarget()

        @objc func toggle(_ sender: Any?) { WindowStylePreferences.shared.isMockup.toggle() }

        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            item.state = WindowStylePreferences.shared.isMockup ? .on : .off
            return true
        }
    }
}
#endif
