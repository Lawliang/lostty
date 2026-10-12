import Foundation

/// How an attached tmux client ended.
public enum AttachEnd: Equatable, Sendable {
    /// The channel finished: tmux exited (the session ended, or someone
    /// detached this client). The window should close.
    case exited(Int32)
    /// The connection broke. Show "reconnecting…" and attach again.
    case lost

    /// `finished`: the channel closed normally, with `exitCode` if the
    /// remote reported one.
    public static func from(finished: Bool, exitCode: Int?) -> AttachEnd {
        finished ? .exited(Int32(truncatingIfNeeded: exitCode ?? 0)) : .lost
    }
}

/// What the screen showing a remote terminal hears about its connection.
public enum RemoteLinkStatus: Equatable, Sendable {
    /// Attached (again).
    case attached
    /// Dropped, or couldn't connect; reconnecting with backoff.
    case lost
    /// tmux exited: the session ended or this client was detached.
    case exited(Int32)
    /// Gave up with a message in the terminal (host key changed, key refused).
    case stopped
}

/// Delays between reconnect attempts: quick at first, then every 15 s.
public struct ReconnectPolicy: Sendable {
    private static let delays: [TimeInterval] = [0.5, 1, 2, 4, 8, 15]
    private var attempt = 0

    public init() {}

    public mutating func nextDelay() -> TimeInterval {
        let delay = Self.delays[min(attempt, Self.delays.count - 1)]
        attempt += 1
        return delay
    }

    public mutating func reset() {
        attempt = 0
    }
}
