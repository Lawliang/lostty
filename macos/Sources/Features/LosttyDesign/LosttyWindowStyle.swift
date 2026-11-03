#if os(macOS)
import AppKit
import GhosttyKit

/// Lostty's two window styles. Mockup, the terminal reskin's and the
/// default: a terminal with no skin is near-black purple with near-white
/// text, the bars are a gray-purple a step lighter, and a card has a short
/// soft shadow and no edge. Classic: the title and bottom bars take the
/// panes' color. View → Classic Window Style switches to it.
enum LosttyWindowStyle {
    static let key = "LosttyClassicWindowStyle"

    /// Read from any thread (a config reload).
    static var isMockup: Bool { !UserDefaults.ghostty.bool(forKey: key) }

    /// The mockup's terminal text, background and bars.
    static let mockupText = RGB(r: 0xE8, g: 0xE2, b: 0xEE)
    static let mockupBackground = RGB(r: 0x17, g: 0x14, b: 0x1B)
    static let mockupBar = RGB(r: 0x2C, g: 0x28, b: 0x32)

    /// A card's title bar and bottom bar: the mockup's 34pt, or a standard
    /// title bar's.
    static var barHeight: CGFloat {
        isMockup ? 34 : NSWindow.frameRect(forContentRect: .zero, styleMask: [.titled]).height
    }

    /// The title and bottom bars' color over panes of `background`: the
    /// mockup's gray-purple over its own terminal, else a step brighter
    /// (dimmer over a light pane) at the same hue and saturation, so each
    /// skin's bars stay its color. Mixing in white grayed them.
    static func bar(over background: NSColor) -> NSColor {
        guard isMockup else { return background }
        return background.usingColorSpace(.sRGB) == nsColor(mockupBackground) ? nsColor(mockupBar) : stepped(background)
    }

    private static func stepped(_ color: NSColor) -> NSColor {
        guard let hsb = color.usingColorSpace(.sRGB) else { return color }
        let step: CGFloat = color.isLightColor ? -0.09 : 0.09
        return NSColor(
            colorSpace: .sRGB, hue: hsb.hueComponent, saturation: hsb.saturationComponent,
            brightness: min(1, max(0, hsb.brightnessComponent + step)), alpha: hsb.alphaComponent)
    }

    /// A title over panes showing `skin`: the terminal's text color, a
    /// little faded, as the mockup's is.
    static func titleColor(skin: Skin?, bar: NSColor) -> NSColor {
        if let foreground = skin?.foreground { return nsColor(foreground).withAlphaComponent(0.8) }
        return bar.isLightColor ? NSColor(white: 0.2, alpha: 1) : nsColor(mockupText).withAlphaComponent(0.8)
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

    /// The mockup's terminal: its 12.5pt text, its colors and dim text,
    /// with the ANSI colors in the same tone.
    private static let mockupColors = """
        font-size = 12.5
        background = #17141B
        foreground = #E8E2EE
        cursor-color = #E8E2EE
        selection-background = #3A3442
        palette = 0=#2C2832
        palette = 1=#E8737E
        palette = 2=#5FCB8A
        palette = 3=#E0B55A
        palette = 4=#6FA8FF
        palette = 5=#D58AD0
        palette = 6=#5CC6C9
        palette = 7=#E8E2EE
        palette = 8=#8C8496
        palette = 9=#F29AA2
        palette = 10=#8ADBA9
        palette = 11=#ECCB85
        palette = 12=#9DC3FF
        palette = 13=#E3ADDF
        palette = 14=#8AD8DA
        palette = 15=#F1EEF5

        """
}

/// View → Classic Window Style.
@MainActor
final class WindowStylePreferences: ObservableObject {
    static let shared = WindowStylePreferences()

    @Published var isMockup = LosttyWindowStyle.isMockup {
        didSet {
            guard isMockup != oldValue else { return }
            UserDefaults.ghostty.set(!isMockup, forKey: LosttyWindowStyle.key)
            (NSApp.delegate as? AppDelegate)?.ghostty.reloadConfig()
        }
    }

    static func installMenuItem(before anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Classic Window Style", action: #selector(MenuTarget.toggle(_:)), keyEquivalent: "")
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
            item.state = WindowStylePreferences.shared.isMockup ? .off : .on
            return true
        }
    }
}
#endif
