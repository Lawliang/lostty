#if os(macOS)
import Foundation

/// What one of Lostty's own Claude runs was for.
enum LosttyRunSource: String, Codable, Sendable {
    case observer, branchSummary
}

/// One Claude run Lostty started by itself, and its tokens per model.
struct LosttyRun: Codable, Equatable, Sendable {
    var at: Date
    var source: LosttyRunSource
    var tokens: [String: TokenCounts]
}

/// The usage breakdown's memory across launches (usage breakdown spec §2,
/// §3): the Claude conversation files Lostty panes reported, and Lostty's
/// own runs. Paths and token counts only, never conversation text. Kept 8
/// days, a day past the weekly window. Safe from any thread: runs record
/// from the background threads they finish on.
final class UsageLedger: @unchecked Sendable {
    static let shared = UsageLedger(url: defaultURL)
    static let keep: TimeInterval = 8 * 24 * 3600

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lostty/usage-ledger.json")
    }

    private struct Contents: Codable {
        /// Resolved conversation path → when a pane last reported it.
        var conversations: [String: Date] = [:]
        var runs: [LosttyRun] = []
    }

    private let url: URL
    private let lock = NSLock()
    private var contents: Contents

    /// An unreadable file reads as empty; the next change rewrites it.
    init(url: URL) {
        self.url = url
        contents = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(Contents.self, from: $0) } ?? Contents()
    }

    /// A pane's agent named its conversation file at a turn's end. Only
    /// Claude's own conversations count (TranscriptLocation decides what
    /// may be read); Codex's use another plan.
    func reported(
        _ path: String,
        at now: Date = Date(),
        locate: (String) -> TranscriptLocation? = { TranscriptLocation.allowed($0) }
    ) {
        guard let location = locate(path), location.agent == .claude else { return }
        // Reported under a minute ago: no need to rewrite the file (every
        // turn end reports, and the window is days long).
        lock.lock()
        let last = contents.conversations[location.url.path]
        lock.unlock()
        if let last, now.timeIntervalSince(last) >= 0, now.timeIntervalSince(last) < 60 { return }
        change(now) { $0.conversations[location.url.path] = now }
    }

    /// One of Lostty's runs used `tokens` (from ClaudeCLI.usage).
    func record(_ tokens: [String: TokenCounts], source: LosttyRunSource, at now: Date = Date()) {
        guard !tokens.isEmpty else { return }
        change(now) { $0.runs.append(LosttyRun(at: now, source: source, tokens: tokens)) }
    }

    /// The conversation files reported in the last 8 days.
    func conversations(now: Date = Date()) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return contents.conversations.filter { now.timeIntervalSince($0.value) < Self.keep }
            .keys.sorted().map { URL(fileURLWithPath: $0) }
    }

    /// Lostty's runs in the last 8 days, oldest first.
    func runs(now: Date = Date()) -> [LosttyRun] {
        lock.lock()
        defer { lock.unlock() }
        return contents.runs.filter { now.timeIntervalSince($0.at) < Self.keep }
    }

    /// Edits, drops what's older than 8 days, and saves.
    private func change(_ now: Date, _ edit: (inout Contents) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        edit(&contents)
        contents.conversations = contents.conversations.filter { now.timeIntervalSince($0.value) < Self.keep }
        contents.runs.removeAll { now.timeIntervalSince($0.at) >= Self.keep }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(contents) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
#endif
