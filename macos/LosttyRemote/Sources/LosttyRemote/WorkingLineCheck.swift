import Foundation

/// Notices Claude stopping without saying so. An interrupt (Esc, Ctrl+C)
/// sends no Stop hook, and Claude Code no longer animates the pane's title,
/// so the Mac's edge trace kept racing. While Claude works, its working
/// line ("✳ Smooshing… (1m 12s · …)") shows over its input box; a racing
/// pane whose screen has gone without one for a few checks in a row has
/// stopped. Not at first: a turn's line takes a moment to appear.
public struct WorkingLineCheck: Sendable {
    /// A turn this young may not show its line yet.
    public static let grace: TimeInterval = 6
    /// Checks in a row without the line before it counts.
    public static let missesToStop = 2

    private var misses: [UUID: Int] = [:]

    public init() {}

    /// `racing`: the panes whose trace runs for Claude itself, and since
    /// when. `showing`: for those whose screen was read, whether it shows
    /// the working line. The panes that stopped.
    public mutating func check(racing: [UUID: Date], showing: [UUID: Bool], now: Date) -> [UUID] {
        misses = misses.filter { racing[$0.key] != nil }
        var stopped: [UUID] = []
        for (id, since) in racing {
            guard now.timeIntervalSince(since) >= Self.grace, let shows = showing[id] else { continue }
            if shows {
                misses[id] = nil
                continue
            }
            let count = (misses[id] ?? 0) + 1
            if count >= Self.missesToStop {
                misses[id] = nil
                stopped.append(id)
            } else {
                misses[id] = count
            }
        }
        return stopped
    }
}
