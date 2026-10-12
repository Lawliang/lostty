#if os(macOS)
import AppKit

/// What clicking a session in the Branches panel does.
@MainActor
enum BranchesActions {
    /// A pane comes to the front; a session only the phone shows opens in a
    /// new tab of this window.
    static func open(_ session: BranchSession) {
        switch session.origin {
        case .pane(let id):
            PaneFocus.focus(id)
        case .phone(let sessionID):
            guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
            SessionsUI.openInTab(sessionID, from: NSApp.keyWindow, ghostty: ghostty)
        }
    }
}
#endif
