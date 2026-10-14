#if os(macOS)
import AppKit
import SwiftUI

/// "Lostty Settings…" in the app menu, and its window. ⌘, (Preferences…)
/// still opens the config file.
@MainActor
enum SettingsUI {
    private static var window: NSWindow?

    static func installMenuItem(after anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Lostty Settings…", action: #selector(MenuTarget.open(_:)), keyEquivalent: "")
        item.target = MenuTarget.shared
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
    }

    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(sidebar: .shared, observer: .shared))
            let window = NSWindow(contentViewController: host)
            window.title = "Lostty Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        @objc func open(_ sender: Any?) { SettingsUI.show() }
    }
}
#endif
