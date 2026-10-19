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
        let view = NSMenuItem(title: "Canvas View", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Canvas View")
        let arrows: NSEvent.ModifierFlags = [.control, .option, .command]
        for item in [
            item("Jump to What Needs You", #selector(jump(_:)), "j", [.control, .command]),
            item("Zoom to Fit", #selector(zoomToFit(_:)), "0", [.control, .command]),
            item("Zoom Card to 100%", #selector(zoomCard(_:)), "1", [.control, .command]),
            .separator(),
            item("Select Card Left", #selector(selectCard(_:)), Self.key(NSLeftArrowFunctionKey), arrows, tag: 0),
            item("Select Card Right", #selector(selectCard(_:)), Self.key(NSRightArrowFunctionKey), arrows, tag: 1),
            item("Select Card Above", #selector(selectCard(_:)), Self.key(NSUpArrowFunctionKey), arrows, tag: 2),
            item("Select Card Below", #selector(selectCard(_:)), Self.key(NSDownArrowFunctionKey), arrows, tag: 3),
        ] {
            submenu.addItem(item)
        }
        view.submenu = submenu
        return [item("Canvas", #selector(showCanvas(_:)), "k", [.control, .command]), view]
    }

    private static func key(_ code: Int) -> String {
        UnicodeScalar(code).map { String(Character($0)) } ?? ""
    }

    private func item(
        _ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags, tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        item.tag = tag
        return item
    }

    @objc private func showCanvas(_ sender: Any?) {
        guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
        CanvasController.show(ghostty)
    }

    @objc private func jump(_ sender: Any?) {
        CanvasController.key?.jump()
    }

    @objc private func zoomToFit(_ sender: Any?) {
        CanvasController.key?.zoomToFit()
    }

    @objc private func zoomCard(_ sender: Any?) {
        guard let canvas = CanvasController.key, let card = canvas.focusedCard else { return }
        canvas.zoom(to: card)
    }

    @objc private func selectCard(_ sender: NSMenuItem) {
        let directions: [CanvasModel.Direction] = [.left, .right, .up, .down]
        guard directions.indices.contains(sender.tag) else { return }
        CanvasController.key?.moveFocus(directions[sender.tag])
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(showCanvas(_:)): true
        default: CanvasController.key != nil
        }
    }
}
#endif
