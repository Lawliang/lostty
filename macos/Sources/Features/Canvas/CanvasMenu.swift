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
        return [
            item("Canvas", #selector(showCanvas(_:)), "k", [.control, .command]),
            item("Move to Canvas", #selector(moveToCanvas(_:)), "", []),
            item("Move All Windows to Canvas", #selector(moveAllToCanvas(_:)), "", []),
            item("Move to Window", #selector(moveToWindow(_:)), "", []),
            view,
        ]
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

    private var ghostty: Ghostty.App? { (NSApp.delegate as? AppDelegate)?.ghostty }
    private var keyTerminal: TerminalController? { NSApp.keyWindow?.windowController as? TerminalController }

    /// Opening an empty canvas while windows are open asks to bring them.
    @objc private func showCanvas(_ sender: Any?) {
        guard let ghostty else { return }
        let windows = CanvasImport.windows(first: keyTerminal)
        if CanvasController.shared?.cards.isEmpty != false, !windows.isEmpty,
           CanvasImport.shouldMoveAll(windows.count, opening: true) {
            CanvasImport.move(ghostty, windows, focus: keyTerminal)
        } else {
            CanvasController.show(ghostty)
        }
    }

    /// Moving one window while others are open asks to move them too.
    @objc private func moveToCanvas(_ sender: Any?) {
        guard let ghostty, let window = keyTerminal else { return }
        let windows = CanvasImport.windows(first: window)
        let all = windows.count > 1 && CanvasImport.shouldMoveAll(windows.count, opening: false)
        CanvasImport.move(ghostty, all ? windows : [window], focus: window)
    }

    @objc private func moveAllToCanvas(_ sender: Any?) {
        guard let ghostty else { return }
        CanvasImport.move(ghostty, CanvasImport.windows(first: keyTerminal), focus: keyTerminal)
    }

    @objc private func moveToWindow(_ sender: Any?) {
        guard let canvas = CanvasController.key, let card = canvas.focusedCard else { return }
        canvas.moveToWindow(card)
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
        case #selector(moveToCanvas(_:)): NSApp.keyWindow?.windowController is TerminalController
        case #selector(moveAllToCanvas(_:)): !TerminalController.all.isEmpty
        case #selector(moveToWindow(_:)): CanvasController.key?.focusedCard != nil
        default: CanvasController.key != nil
        }
    }
}
#endif
