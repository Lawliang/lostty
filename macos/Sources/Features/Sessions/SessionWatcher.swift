#if os(macOS)
import Foundation
import LosttyRemote

extension Notification.Name {
    /// Lostty's tmux sessions changed. Posted on the main queue.
    static let losttySessionsChanged = Notification.Name("LosttySessionsChanged")
}

/// Lostty Mobile: waits on tmux's `lostty-changed` channel on its own thread
/// and posts `.losttySessionsChanged` after every wake. Gives the tmux server
/// the change hooks whenever it (re)appears: one started by an older Lostty,
/// or from an older bundled tmux.conf, has none.
final class SessionWatcher: @unchecked Sendable {
    static let shared = SessionWatcher()

    /// `-f /dev/null`: waiting must never start a server that reads the
    /// user's ~/.tmux.conf.
    static let waitArgs = ["-f", "/dev/null", "wait-for", TmuxRemote.changedChannel]

    /// How long a wake waits for more before it is posted: one change in
    /// Lostty often signals several times (a state write, a title, a note),
    /// and every post makes each listener ask tmux again.
    static let settle: TimeInterval = 0.2

    private let lock = NSLock()
    private var started = false
    private var posting = false

    func start() {
        let first: Bool = lock.withLock {
            defer { started = true }
            return !started
        }
        guard first else { return }
        let thread = Thread { [self] in loop() }
        thread.name = "Lostty session watcher"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Seconds to rest before waiting again. A wait that failed at once
    /// means no server: look again in 5 s instead of spinning.
    static func pause(woke: Bool, waited: TimeInterval) -> TimeInterval {
        !woke && waited < 1 ? 5 : 0
    }

    /// Posts once for every wake within `settle`, after the last of them
    /// could have changed tmux.
    private func postSoon() {
        let first: Bool = lock.withLock {
            defer { posting = true }
            return !posting
        }
        guard first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [self] in
            lock.withLock { posting = false }
            NotificationCenter.default.post(name: .losttySessionsChanged, object: nil)
        }
    }

    private func loop() {
        let client = TmuxClient()
        guard client.tmuxPath != nil else { return }
        // Up to 10 minutes per wait; a timeout just waits again.
        let waiter = TmuxClient(timeout: 600)
        var hooksSet = false
        while true {
            if !hooksSet { hooksSet = client.run(TmuxHooks.setArgs) != nil }
            postSoon()
            let start = Date()
            let woke = waiter.run(Self.waitArgs) != nil
            // A failed wait may mean a new server: set the hooks again.
            if !woke { hooksSet = false }
            let rest = Self.pause(woke: woke, waited: Date().timeIntervalSince(start))
            if rest > 0 { Thread.sleep(forTimeInterval: rest) }
        }
    }
}
#endif
