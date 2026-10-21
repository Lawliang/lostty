#if os(macOS)
import AppKit

/// Keeps `LastSession` up to date while Lostty runs: a couple of seconds
/// after the windows, tabs, splits, canvas cards, a pane's folder or an
/// agent's conversation change, and only when the snapshot did. Saved
/// again on the way out (quit, restart, shutdown) and before the Mac
/// sleeps. A few KB of JSON; nothing touches the terminals.
@MainActor
final class LastSessionStore {
    static let shared = LastSessionStore()

    /// How long after the last change it saves, so a drag saves once.
    static let delay: TimeInterval = 2
    /// How long saving pauses once the Mac starts shutting down: the
    /// panes' sessions end on the way, and must not be saved as closed.
    static let shutdownPause: TimeInterval = 60

    private let url: URL
    /// The agent panes' conversations, from each turn's end.
    private var conversations: [UUID: PaneConversation] = [:]
    private var last: LastSession?
    private var pending: DispatchWorkItem?
    private var started = false
    private var paused = false
    private var observers: [NSObjectProtocol] = []

    init(url: URL = LastSession.standardURL) {
        self.url = url
    }

    /// Once the windows are back (or Continue is answered): from here on
    /// it saves. Panes still open from the saved session (after Restart to
    /// Update, or Continue) keep its conversations until their next turn.
    func start() {
        guard !started else { return }
        started = true
        if let saved = LastSession.load(from: url) {
            let open = Set(Self.openPanes().map(\.uuidString))
            for (pane, conversation) in saved.conversations where open.contains(pane) {
                if let id = UUID(uuidString: pane) { conversations[id] = conversation }
            }
        }
        observe()
        noteChange()
    }

    /// Something in the session changed: save once things settle.
    func noteChange() {
        guard started, !paused else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.save() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
    }

    /// A pane's agent finished a turn in the conversation file at `path`.
    func conversation(_ pane: UUID, transcript path: String) {
        guard let conversation = PaneConversation.from(transcript: path), conversations[pane] != conversation else { return }
        conversations[pane] = conversation
        noteChange()
    }

    /// A pane's agent exited, or the pane closed.
    func agentGone(_ pane: UUID) {
        guard conversations.removeValue(forKey: pane) != nil else { return }
        noteChange()
    }

    /// Lostty is quitting: the session as it is now, and nothing after
    /// (its sessions end on the way out).
    func saveForQuit() {
        guard started, !paused else { return }
        save(force: true)
        paused = true
    }

    private func save(force: Bool = false) {
        pending?.cancel()
        pending = nil
        guard let windows = WindowSnapshot.capture() else {
            // Nothing open: nothing to continue.
            if last != nil || force { LastSession.delete(at: url) }
            last = nil
            return
        }
        let panes = Self.openPanes()
        let open = Set(panes)
        let session = LastSession(
            at: Date(), windows: windows, panes: panes.map(\.uuidString),
            conversations: Dictionary(uniqueKeysWithValues: conversations.filter { open.contains($0.key) }
                .map { ($0.key.uuidString, $0.value) }))
        if !force, let last, last.sameContents(as: session) { return }
        do {
            try session.save(to: url)
            last = session
        } catch {
            Ghostty.logger.warning("last session: couldn't save (\(error.localizedDescription))")
        }
    }

    /// The panes a snapshot holds: every terminal window's and the canvas's.
    private static func openPanes() -> [UUID] {
        let controllers: [BaseTerminalController] = TerminalController.all + (CanvasController.shared?.cards ?? [])
        return controllers.flatMap { $0.surfaceTree.map(\.id) }
    }

    private func observe() {
        let center = NotificationCenter.default
        let windowEvents: [Notification.Name] = [
            NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ]
        for name in windowEvents {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow,
                      window.windowController is TerminalController || window.windowController is CanvasController
                else { return }
                MainActor.assumeIsolated { LastSessionStore.shared.noteChange() }
            })
        }
        observers.append(center.addObserver(forName: .losttySurfaceTreeDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LastSessionStore.shared.noteChange() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LastSessionStore.shared.save(force: true) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LastSessionStore.shared.shuttingDown() }
        })
    }

    /// Shutdown, restart or log out: save now, then pause, so the sessions
    /// ending on the way aren't saved as closed. Back after a while, in case
    /// it was cancelled.
    private func shuttingDown() {
        guard started, !paused else { return }
        save(force: true)
        paused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shutdownPause) { [weak self] in
            MainActor.assumeIsolated { self?.paused = false }
        }
    }
}
#endif
