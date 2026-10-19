#if os(macOS)
import AppKit

/// Lostty Beta's canvas items in the Window menu, above Bring All to Front.
@MainActor
final class CanvasMenu: NSObject, NSMenuItemValidation {
    static let shared = CanvasMenu()

    /// Nothing in the stable app.
    static func install(before anchor: NSMenuItem?, channel: LosttyChannel = .current) {
        guard channel.hasCanvas, let anchor, let menu = anchor.menu else { return }
        var index = menu.index(of: anchor)
        for item in shared.items() + [.separator()] {
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    private func items() -> [NSMenuItem] {
        [
            item("Canvas", #selector(showCanvas(_:)), "k", [.control, .command]),
        ]
    }

    private func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        return item
    }

    @objc private func showCanvas(_ sender: Any?) {
        guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
        CanvasController.show(ghostty)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(showCanvas(_:)): true
        default: CanvasController.key != nil
        }
    }
}
#endif
