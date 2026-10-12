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

    private let lock = NSLock()
    private var started = false

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

    private func loop() {
        let client = TmuxClient()
        guard client.tmuxPath != nil else { return }
        // Up to 10 minutes per wait; a timeout just waits again.
        let waiter = TmuxClient(timeout: 600)
        var hooksSet = false
        while true {
            if !hooksSet { hooksSet = client.run(TmuxHooks.setArgs) != nil }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .losttySessionsChanged, object: nil)
            }
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
