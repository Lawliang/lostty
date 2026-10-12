#if os(macOS)
import AppKit
import SwiftUI

/// "Phone Access…" in the app menu, and its window.
@MainActor
enum PhoneAccessUI {
    private static var window: NSWindow?
    private static let store = PhoneAccessStore()

    static func installMenuItem(after anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Phone Access…", action: #selector(MenuTarget.open(_:)), keyEquivalent: "")
        item.target = MenuTarget.shared
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
    }

    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: PhoneAccessView().environmentObject(store))
            let window = NSWindow(contentViewController: host)
            window.title = "Phone Access"
            window.styleMask = [.titled, .closable, .resizable]
            // Always dark: a branded setup window, one palette.
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(LosttyTheme.background)
            window.titlebarAppearsTransparent = true
            window.contentMinSize = NSSize(width: 560, height: 520)
            window.contentMaxSize = NSSize(width: 560, height: 4000)
            window.isReleasedWhenClosed = false
            window.center()
            // Re-check when the customer comes back from a fix (Terminal,
            // System Settings, Tailscale); only this window, so switching
            // terminal windows doesn't run the checks.
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    if !store.checking && store.pairing == nil { store.refresh() }
                }
            }
            // A code left showing after the window closes would keep
            // listening for a phone nobody is watching for.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { store.stopPairing() }
            }
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        @objc func open(_ sender: Any?) { PhoneAccessUI.show() }
    }
}
#endif
