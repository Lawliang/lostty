import Foundation

/// How long since the person last used the phone app: a touch, a key, or
/// coming back to it. After `limit` without use the app rests (closes its
/// connections and stops drawing) and Face ID is asked again; any use
/// starts the `limit` over.
public struct AwayClock: Equatable, Sendable {
    public static let limit: TimeInterval = 30 * 60

    public private(set) var lastUsed: Date

    public init(now: Date) {
        lastUsed = now
    }

    /// Used at `date`. An earlier use (a key the terminal saw before the
    /// last touch) doesn't wind it back.
    public mutating func used(at date: Date) {
        if date > lastUsed { lastUsed = date }
    }

    /// When the app rests unless it's used before then.
    public var restsAt: Date { lastUsed.addingTimeInterval(Self.limit) }

    public func isAway(now: Date) -> Bool {
        now >= restsAt
    }
}
