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

    /// Errors the user or pairing must resolve: a cancelled Face ID
    /// prompt, a refused key, a changed host key. Retrying only knocks
    /// (or re-prompts) again.
    public static func stopsWatch(for error: Error) -> Bool {
        switch error as? RemoteError {
        case .authenticationCancelled?, .keyRejected?, .hostKeyChanged?: true
        default: false
        }
    }

    /// A watch that ended: only one that heard a change was a healthy
    /// connection. With no tmux server it ends at once, and the delay must
    /// keep growing rather than reconnect every 0.5 s.
    public mutating func watchEnded(deliveredChange: Bool) {
        if deliveredChange { reset() }
    }
}

/// Whether the phone's live session list should be watching. A watch that
/// stopped on an error the user must resolve (`ReconnectPolicy.stopsWatch`)
/// stays stopped until they ask: the Face ID sheet itself makes the app
/// inactive and then active again, so restarting on every `.active` would
/// prompt in a loop.
public struct ListWatchGate: Equatable, Sendable {
    /// The list is on screen.
    public var listVisible = false
    public private(set) var appActive = true
    /// Stopped for an error the user must resolve.
    public private(set) var held = false

    public init() {}

    public func wanted(hasHosts: Bool) -> Bool {
        listVisible && appActive && hasHosts && !held
    }

    /// The watch failed with `error`. True when it must stop (and stays
    /// stopped until `userAsked` or a trip to the background).
    public mutating func watchFailed(_ error: Error) -> Bool {
        let stops = ReconnectPolicy.stopsWatch(for: error)
        if stops { held = true }
        return stops
    }

    /// Pull to refresh, coming back to the list, new settings or pairing.
    public mutating func userAsked() {
        held = false
    }

    /// `.active`. Only a return from the background (not the Face ID
    /// sheet or Control Center going away) tries again by itself.
    public mutating func becameActive(afterBackground: Bool) {
        appActive = true
        if afterBackground { held = false }
    }

    public mutating func wentToBackground() {
        appActive = false
    }
}
