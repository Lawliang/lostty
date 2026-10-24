#if os(macOS)
import AppKit

/// How the Claude trace looks while Claude works: each pane's own skin
/// trace, the same without the glowing circle at its head, or the
/// website's light circling each working pane (WindowTrace).
/// Saved in user defaults and set from Lostty → Claude Trace Style.
enum TraceStyle: String, CaseIterable {
    case skin, skinNoGlow, window

    static let defaultsKey = "LosttyTraceStyle"
    /// What a new Lostty shows until the person picks another.
    static let initial: TraceStyle = .skin

    var title: String {
        switch self {
        case .skin: "Skin Traces"
        case .skinNoGlow: "Skin Traces, No Head Glow"
        case .window: "Window Light"
        }
    }

    static func current(in defaults: UserDefaults = .ghostty) -> TraceStyle {
        defaults.string(forKey: defaultsKey).flatMap(TraceStyle.init(rawValue:)) ?? initial
    }

    static func save(_ style: TraceStyle, in defaults: UserDefaults = .ghostty) {
        defaults.set(style.rawValue, forKey: defaultsKey)
    }
}

/// The Lostty → Claude Trace Style submenu, one checkmarked item per style.
@MainActor
final class TraceStyleMenu: NSObject, NSMenuDelegate {
    static let shared = TraceStyleMenu()

    /// Returns the item, so the Trace Path menu can follow it.
    @discardableResult
    static func install(after anchor: NSMenuItem) -> NSMenuItem? {
        guard let menu = anchor.menu else { return nil }
        let submenu = NSMenu(title: "Claude Trace Style")
        submenu.delegate = shared
        for style in TraceStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = shared
            item.representedObject = style.rawValue
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Claude Trace Style", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let current = TraceStyle.current()
        for item in menu.items where item.representedObject != nil {
            item.state = item.representedObject as? String == current.rawValue ? .on : .off
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = TraceStyle(rawValue: raw) else { return }
        TraceStyle.save(style)
    }
}
#endif
