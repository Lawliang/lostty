#if os(macOS)
import AppKit
import LosttyRemote

/// Lostty Mobile on the Mac: after every tmux change, shows session labels
/// (set here or on the phone) as tab titles, and counts a phone attaching to
/// a waiting Claude as seeing it. It only reads tmux on a wake, so a wake
/// never causes another wake.
@MainActor
final class SessionSync {
    static let shared = SessionSync()

    /// This Lostty's panes whose session has a label.
    private(set) var labels: [UUID: String] = [:]
    private var observer: NSObjectProtocol?
    private let pid = ProcessInfo.processInfo.processIdentifier
    /// The SSH clients attached at the last refresh: only a new attach
    /// counts as seeing, so a phone left attached hides nothing later.
    private var previouslyAttached: Set<AttachedClient> = []

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .losttySessionsChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SessionSync.shared.refresh() }
        }
    }

    func refresh() {
        Task {
            let (sessions, phones) = await Task.detached(priority: .utility) {
                (TmuxClient().remoteSessions(), Set(AttachedPhones.currentClients()))
            }.value
            apply(sessions, phoneAttached: phones)
        }
    }

    func apply(_ sessions: [RemoteSession], phoneAttached: Set<AttachedClient>) {
        let next = Self.labels(sessions, pid: pid)
        if next != labels {
            labels = next
            for controller in NSApp.windows.compactMap({ $0.windowController as? BaseTerminalController }) {
                controller.applySessionLabel()
            }
        }
        let newlyAttached = Self.newlyAttached(previous: previouslyAttached, current: phoneAttached)
        previouslyAttached = phoneAttached
        for pane in Self.panesWithAPhone(sessions, phoneAttached: newlyAttached, pid: pid) {
            ClaudeRuntime.shared.seenElsewhere(pane)
        }
    }

    /// Rename Tab…: names the session showing `pane` (nil clears it). The
    /// label map follows on the change event the write sends.
    func setLabel(_ typed: String?, forPane pane: UUID) {
        let label = typed.flatMap(SessionLabel.cleanLabel)
        let pid = self.pid
        Task.detached(priority: .utility) {
            TmuxClient().setLabel(label, surface: pane, ownedBy: pid)
        }
    }

    nonisolated static func labels(_ sessions: [RemoteSession], pid: Int32) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for session in sessions where session.owner == pid {
            guard let label = session.label, let pane = session.surface.flatMap(UUID.init(uuidString:)) else { continue }
            result[pane] = label
        }
        return result
    }

    /// Sessions a client attached to since the last refresh: only a new
    /// attach counts as seeing a waiting Claude. By client, not session: a
    /// phone reconnecting while its dropped connection is still listed
    /// (sshd takes up to a minute to notice) is still a new attach.
    nonisolated static func newlyAttached(previous: Set<AttachedClient>, current: Set<AttachedClient>) -> Set<String> {
        Set(current.subtracting(previous).map(\.session))
    }

    nonisolated static func panesWithAPhone(_ sessions: [RemoteSession], phoneAttached: Set<String>, pid: Int32) -> [UUID] {
        sessions
            .filter { $0.owner == pid && phoneAttached.contains($0.id) }
            .compactMap { $0.surface.flatMap(UUID.init(uuidString:)) }
    }
}

/// The tab title a label gives the focused pane.
struct SessionTitleOverride: Equatable {
    var title: String?
    /// The title came from a label, so it goes when the label does (or
    /// focus moves to a pane without one).
    var fromLabel: Bool

    static func next(current: String?, fromLabel: Bool, label: String?) -> SessionTitleOverride {
        if let label { return SessionTitleOverride(title: label, fromLabel: true) }
        if fromLabel { return SessionTitleOverride(title: nil, fromLabel: false) }
        return SessionTitleOverride(title: current, fromLabel: false)
    }
}
#endif
