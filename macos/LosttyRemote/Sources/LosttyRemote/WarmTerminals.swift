import Foundation

/// Terminals kept open after the phone goes back to the list, so opening one
/// again is instant: the most recent `capacity`, each for `keepFor` after it
/// was put back. A terminal is keyed by its session id and name (ids restart
/// with the Mac's tmux server, so an id alone can name another session).
/// Whatever comes out (`put` evicting, `expired`, `remove`) is for the
/// caller to close.
public struct WarmTerminals<Value> {
    public struct Key: Hashable, Sendable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var capacity: Int
    public var keepFor: TimeInterval
    /// Oldest first.
    private var entries: [(key: Key, value: Value, until: Date)] = []

    public init(capacity: Int = 3, keepFor: TimeInterval = 5 * 60) {
        self.capacity = capacity
        self.keepFor = keepFor
    }

    public var count: Int { entries.count }
    public var keys: [Key] { entries.map(\.key) }
    public var values: [Value] { entries.map(\.value) }

    /// Keeps `value` warm until `now + keepFor`, replacing any for the same
    /// key. Returns what no longer fits (and the one replaced).
    public mutating func put(_ key: Key, _ value: Value, now: Date) -> [Value] {
        var out = remove { $0 == key }
        entries.append((key, value, now.addingTimeInterval(keepFor)))
        while entries.count > capacity { out.append(entries.removeFirst().value) }
        return out
    }

    /// The warm terminal for `key`, no longer warm: it is in use again.
    public mutating func take(_ key: Key) -> Value? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        return entries.remove(at: index).value
    }

    /// Those kept past their time.
    public mutating func expired(now: Date) -> [Value] {
        remove(byDate: now)
    }

    /// The next time one expires, to check again then.
    public var nextExpiry: Date? { entries.map(\.until).min() }

    @discardableResult
    public mutating func remove(where matches: (Key) -> Bool) -> [Value] {
        let gone = entries.filter { matches($0.key) }.map(\.value)
        entries.removeAll { matches($0.key) }
        return gone
    }

    public mutating func removeAll() -> [Value] {
        defer { entries = [] }
        return entries.map(\.value)
    }

    private mutating func remove(byDate now: Date) -> [Value] {
        let gone = entries.filter { $0.until <= now }.map(\.value)
        entries.removeAll { $0.until <= now }
        return gone
    }
}
