#if os(macOS)
import Foundation

/// What a restarting Lostty leaves for the one it starts (`LosttyRestart`):
/// written just before it exits, read and deleted at the next launch. One
/// file per build (bundle id), so a Debug build and the installed app never
/// take each other's.
struct RestartHandoff: Codable, Equatable {
    /// The Lostty that wrote it; it must have exited for this to count.
    var pid: Int32
    var at: Date
    /// Each pane's Claude, by pane UUID (restored panes keep their UUIDs).
    var claude: [String: ClaudeCarry]
    var stayAwakeOn: Bool
    /// When Stay Awake was due to end; nil for "until I turn it off".
    var stayAwakeUntil: Date?
    /// The agents ("claude", "codex") that had Lostty's hooks: out of date
    /// after the restart means update them, not that you chose not to.
    var hookAgents: [String]
    /// `NSQuitAlwaysKeepsWindows` before the restart forced it on; nil when unset.
    var keepWindows: Bool?

    /// Older than this, it's not a restart's: a crash's prompt applies.
    static let maxAge: TimeInterval = 120

    static func url(bundleID: String, in folder: URL) -> URL {
        folder.appendingPathComponent("restart-\(bundleID).json")
    }

    static var standardURL: URL {
        url(
            bundleID: Bundle.main.bundleIdentifier ?? "com.lawliang.lostty",
            in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lostty", isDirectory: true))
    }

    /// From a Lostty that has exited, in the last `maxAge` seconds.
    func isFresh(now: Date, isAlive: (Int32) -> Bool) -> Bool {
        let age = now.timeIntervalSince(at)
        return !isAlive(pid) && age >= 0 && age <= Self.maxAge
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// The handoff at `url`, deleted whether or not it reads.
    static func take(from url: URL) -> RestartHandoff? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(RestartHandoff.self, from: data)
    }
}
#endif
