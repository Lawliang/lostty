#if os(macOS)
import AppKit

/// File → Reopen from History: the newest snapshots in the
/// `SessionHistory`, each with when it was saved and what it held. Choosing
/// one reopens what of it isn't open now.
@MainActor
final class SessionHistoryMenu: NSObject, NSMenuDelegate {
    static let shared = SessionHistoryMenu()

    /// How many snapshots the menu lists.
    static let shown = 20

    static func install(after anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Reopen from History", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Reopen from History")
        submenu.delegate = shared
        item.submenu = submenu
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let entries = SessionHistory.standard.entries(max: Self.shown)
        guard !entries.isEmpty else {
            menu.addItem(NSMenuItem(title: "No Snapshots Yet", action: nil, keyEquivalent: ""))
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        for entry in entries {
            let reopenable = SessionRestore.reopenable(entry.session)
            var title = "\(formatter.string(from: entry.session.at)) — \(entry.session.summary)"
            if reopenable == nil { title += " (open now)" }
            let item = NSMenuItem(title: title, action: reopenable == nil ? nil : #selector(reopen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.url
            menu.addItem(item)
        }
    }

    @objc private func reopen(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, let session = LastSession.load(from: url),
              let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
        SessionRestore.reopen(session, ghostty)
    }
}
#endif
