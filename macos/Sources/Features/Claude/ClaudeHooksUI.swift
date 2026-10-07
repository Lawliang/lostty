#if os(macOS)
import AppKit

/// The Claude Integration menu item (spec §5.2). Missing hooks are offered
/// at launch by notification bubbles (HookNotifications).
@MainActor
enum ClaudeHooksUI {
    static func installMenuItem(after anchor: NSMenuItem?) {
        guard let anchor, let menu = anchor.menu else { return }
        let item = NSMenuItem(title: "Claude Integration…", action: #selector(MenuTarget.open(_:)), keyEquivalent: "")
        item.target = MenuTarget.shared
        menu.insertItem(item, at: menu.index(of: anchor) + 1)
    }

    /// Install / Not now / Show changes.
    static func offerInstall(update: Bool) {
        let alert = NSAlert()
        alert.messageText = update ? "Update Lostty's hooks?" : "Show a trace while Claude or Codex is working?"
        alert.informativeText = update
            ? "Lostty's hooks are from an older Lostty, or Codex is missing them. Lostty will update its hooks in "
                + "~/.claude/settings.json and ~/.codex/hooks.json (a backup is saved first)."
            : "Lostty will add its hooks to ~/.claude/settings.json and, if you use Codex, ~/.codex/hooks.json "
                + "(a backup is saved first). They do nothing outside Lostty. You can remove them from "
                + "Lostty → Claude Integration…"
        alert.addButton(withTitle: update ? "Update" : "Install")
        alert.addButton(withTitle: "Not now")
        alert.addButton(withTitle: "Show changes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: run("install")
        case .alertThirdButtonReturn: showChanges(update: update)
        default: break
        }
    }

    static func showChanges(update: Bool) {
        let alert = NSAlert()
        alert.messageText = "Lostty adds these hooks"
        alert.informativeText = "Added to the \"hooks\" section of ~/.claude/settings.json (and ~/.codex/hooks.json "
            + "for Codex, with just the first two events). "
            + "Your other settings and hooks are kept."
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 260)
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.string = ClaudeHooksCLI().run("preview").stdout
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: update ? "Update" : "Install")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { run("install") }
    }

    static func showManager() {
        let status = ClaudeHooksCLI().status()
        let alert = NSAlert()
        alert.messageText = "Claude Integration"
        switch status {
        case .installed?:
            alert.informativeText = "Lostty's Claude hooks are installed. The trace shows while Claude works."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Close")
            if alert.runModal() == .alertFirstButtonReturn { run("remove") }
        case .partial?:
            alert.informativeText = "Lostty's Claude hooks are out of date or incomplete."
            alert.addButton(withTitle: "Update")
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Close")
            switch alert.runModal() {
            case .alertFirstButtonReturn: run("install")
            case .alertSecondButtonReturn: run("remove")
            default: break
            }
        case .notInstalled?:
            offerInstall(update: false)
        case .unreadable?:
            alert.informativeText = "~/.claude/settings.json could not be read as JSON, so Lostty will not "
                + "change it. Fix the file, then try again."
            alert.addButton(withTitle: "Close")
            alert.runModal()
        case nil:
            alert.informativeText = "Could not check the Claude hooks (the Lostty command-line tool did not run)."
            alert.addButton(withTitle: "Close")
            alert.runModal()
        }
    }

    private static func run(_ op: String) {
        let result = ClaudeHooksCLI().run(op)
        guard result.exitCode != 0 else {
            if let message = ClaudeHooksPrompt.successMessage(for: op) {
                let done = NSAlert()
                done.messageText = message
                done.addButton(withTitle: "OK")
                done.runModal()
            }
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Lostty could not \(op) the Claude hooks"
        alert.informativeText = result.stderr.isEmpty ? "Unknown error." : result.stderr
        alert.runModal()
    }

    @MainActor
    final class MenuTarget: NSObject {
        static let shared = MenuTarget()
        @objc func open(_ sender: Any?) { ClaudeHooksUI.showManager() }
    }
}
#endif
