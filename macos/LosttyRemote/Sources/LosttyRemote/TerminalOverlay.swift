import Foundation

/// What covers the phone's terminal: nothing, "reconnecting", or why the
/// session ended. A closed overlay stays until Back to Sessions.
public enum TerminalOverlay: Equatable, Sendable {
    case none
    case reconnecting(since: Date)
    case closed(String)

    public static let reconnectingText = "Connection lost — reconnecting…"
    /// Reconnecting this long also offers Back to Sessions.
    public static let backAfter: TimeInterval = 30

    public var message: String? {
        switch self {
        case .none: nil
        case .reconnecting: Self.reconnectingText
        case .closed(let reason): reason
        }
    }

    public var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }

    public func offersBack(now: Date) -> Bool {
        switch self {
        case .none: false
        case .reconnecting(let since): now.timeIntervalSince(since) >= Self.backAfter
        case .closed: true
        }
    }

    /// The overlay after a link event. `.exited` changes nothing here: the
    /// screen asks the Mac why, then shows `.closed` or leaves.
    public func after(_ status: RemoteLinkStatus, now: Date) -> TerminalOverlay {
        switch (self, status) {
        case (.closed, _): self
        case (.none, .lost): .reconnecting(since: now)
        case (.reconnecting, .attached), (.reconnecting, .stopped): .none
        default: self
        }
    }
}
