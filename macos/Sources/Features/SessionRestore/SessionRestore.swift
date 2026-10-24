#if os(macOS)
import AppKit
import Combine

/// After the Mac restarts (or Lostty quits), "Continue your last session?":
/// Continue rebuilds every window and the canvas from `LastSession`, each
/// pane starting a new session in its folder, and types `claude --resume`
/// (or `codex resume`) into the panes that had a conversation. Nothing is
/// sent to the agent. Start Fresh opens one new window.
@MainActor
enum SessionRestore {
    /// Whether this launch offers to continue: a last session whose panes'
    /// tmux sessions all ended, and no Restart to Update to finish. Asked
    /// by window restoration too, which stands down so nothing opens twice.
    nonisolated static let offers: Bool = {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !LosttyRestart.restoresFromSnapshot,
              let last = LastSession.load(from: LastSession.standardURL) else { return false }
        return last.isOver(liveSurfaces: Set(TmuxClient().sessions().compactMap(\.surface)))
    }()

    /// How long a pane's shell gets to start before the resume is typed
    /// anyway.
    static let shellWait: TimeInterval = 8

    /// At launch, once the app is up: ask, if there's a session to
    /// continue; either way, the session is kept up to date from then on.
    static func offerAtLaunch(_ ghostty: Ghostty.App) {
        guard offers, let last = LastSession.load(from: LastSession.standardURL) else {
            LastSessionStore.shared.start()
            return
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let alert = NSAlert()
                alert.messageText = "Continue your last session?"
                alert.informativeText = "\(last.summary).\n\(saved(last.at)) Each terminal starts again in its "
                    + "folder, and conversations reopen where they were."
                alert.addButton(withTitle: "Continue")
                alert.addButton(withTitle: "Start Fresh")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    continueSession(last, ghostty)
                } else {
                    LastSession.delete(at: LastSession.standardURL)
                    _ = TerminalController.newWindow(ghostty)
                }
                LastSessionStore.shared.start()
            }
        }
    }

    /// "Saved today at 2:14 PM." / "Saved Oct 19, 2026 at 2:14 PM."
    private static func saved(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        let text = formatter.string(from: date)
        let relative = Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date)
        return "Saved \(relative ? text.prefix(1).lowercased() + text.dropFirst() : text)."
    }

    /// What reopening `session` from the history would bring back now: its
    /// windows and cards whose panes aren't open, and the conversations not
    /// running elsewhere. Nil when all of it is open.
    static func reopenable(_ session: LastSession) -> LastSession? {
        session.reopenable(
            openPanes: Set(LastSessionStore.openPanes().map(\.uuidString)),
            openConversations: LastSessionStore.shared.openConversations)
    }

    /// File → Reopen from History: brings `session` back while Lostty runs,
    /// as Continue does at launch, leaving out what's open now.
    static func reopen(_ session: LastSession, _ ghostty: Ghostty.App) {
        guard let session = reopenable(session) else { return }
        continueSession(session, ghostty)
    }

    private static func continueSession(_ last: LastSession, _ ghostty: Ghostty.App) {
        last.windows.restore(ghostty)
        for (pane, conversation) in last.conversations {
            guard let id = UUID(uuidString: pane), let command = conversation.resumeCommand else { continue }
            resume(id, command)
        }
    }

    /// Types `command` into the pane once its shell is up (it reports its
    /// folder at the first prompt), or after `shellWait`.
    private static func resume(_ pane: UUID, _ command: String) {
        guard let surface = ContextHandoffWiring.surface(pane) else { return }
        let resume = PendingResume()
        resume.watch = surface.$pwd.dropFirst().compactMap { $0 }.first()
            .receive(on: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { resume.type(pane, command) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + shellWait) {
            MainActor.assumeIsolated { resume.type(pane, command) }
        }
    }

    /// One pane's resume, typed once.
    @MainActor
    private final class PendingResume {
        var watch: AnyCancellable?
        private var typed = false

        func type(_ pane: UUID, _ command: String) {
            guard !typed else { return }
            typed = true
            watch = nil
            ContextHandoffWiring.type(pane, [.text(command), .enter])
        }
    }
}
#endif
