#if os(macOS)
import AppKit
import SwiftUI

/// Lostty Mobile on the Mac: reopening sessions a crash left running, and
/// opening sessions no window shows (started on the phone, or kept).
enum SessionsUI {
    /// After a crash, offers to reopen the sessions the previous Lostty
    /// left running. Normal quits end them, so usually there are none.
    @MainActor static func offerOrphansAtLaunch(_ ghostty: Ghostty.App) {
        Task { @MainActor in
            let found = await Task.detached(priority: .utility) {
                TmuxOwnership.orphans(TmuxClient().sessions(), isAlive: ProcessLiveness.isAlive)
            }.value
            let openPanes = Set(NSApp.windows
                .compactMap { $0.windowController as? BaseTerminalController }
                .flatMap { $0.surfaceTree.filter(\.inTmuxSession).map(\.id) })
            let orphans = TmuxOwnership.reopenable(found, openPanes: openPanes)
            guard !orphans.isEmpty else { return }
            let text = SessionsPrompt.reopen(orphans)
            let alert = NSAlert()
            alert.messageText = text.title
            alert.informativeText = text.body
            alert.addButton(withTitle: "Reopen")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                orphans.forEach { open($0, ghostty: ghostty) }
            } else {
                Task.detached(priority: .utility) {
                    let client = TmuxClient()
                    orphans.forEach(client.disown)
                }
            }
        }
    }

    /// Opens a window showing `session`. The launcher re-tags the session
    /// with the new pane and this Lostty.
    @MainActor static func open(_ session: TmuxSession, ghostty: Ghostty.App) {
        guard let config = attachConfig(session.id) else { return }
        _ = TerminalController.newWindow(ghostty, withBaseConfig: config)
    }

    /// Opens session `sessionID` in a new tab of `window` (a new window when
    /// there is none).
    @MainActor static func openInTab(_ sessionID: String, from window: NSWindow?, ghostty: Ghostty.App) {
        guard let config = attachConfig(sessionID) else { return }
        _ = TerminalController.newTab(ghostty, from: window, withBaseConfig: config)
    }

    private static func attachConfig(_ sessionID: String) -> Ghostty.SurfaceConfiguration? {
        guard let binary = Bundle.main.executableURL?.path else { return nil }
        var config = Ghostty.SurfaceConfiguration()
        config.command = SessionLaunch.attachCommand(binary: binary, sessionID: sessionID)
        return config
    }
}

enum SessionsPrompt {
    static func reopen(_ sessions: [TmuxSession]) -> (title: String, body: String) {
        let count = sessions.count
        let title = count == 1 ? "Reopen 1 terminal session?" : "Reopen \(count) terminal sessions?"
        let names = sessions.map(\.name).joined(separator: ", ")
        let body = "Lostty quit unexpectedly while these were open, and they are still running: \(names). "
            + "Not Now keeps them running; open them later from the command palette or the phone."
        return (title, body)
    }
}

/// Sessions the command palette offers ("Open Session: idfk"), refreshed
/// each time the palette opens.
@MainActor
final class SessionsModel: ObservableObject {
    static let shared = SessionsModel()

    @Published private(set) var available: [TmuxSession] = []

    func refresh() {
        Task {
            available = await Task.detached(priority: .userInitiated) {
                TmuxOwnership.available(TmuxClient().sessions(), isAlive: ProcessLiveness.isAlive)
            }.value
        }
    }
}
#endif
