#if os(macOS)
import Foundation

/// Which part of the usage breakdown a use belongs to.
enum UsagePart: Equatable, Sendable {
    case claudeCode, lostty
}

/// One reply's or run's weighted tokens, and when it happened.
struct WeightedUse: Equatable, Sendable {
    var at: Date
    var part: UsagePart
    var weight: Double
}

/// Counts the replies in Lostty panes' Claude conversation files and their
/// subagents' files (usage breakdown spec §4). An actor, so reading runs
/// off the main thread; it remembers how far it read each file, so a
/// count after the first reads only what was added.
actor UsageCounter {
    /// One reply as counted.
    struct Reply: Equatable, Sendable {
        var at: Date
        var weight: Double
    }

    private struct FileState {
        var offset: UInt64 = 0
        /// By `message.id` and `requestId`: one reply is written on several
        /// lines, each with the same id and tokens.
        var replies: [String: Reply] = [:]
    }

    private var files: [String: FileState] = [:]
    private let chunk: Int

    /// `chunk`: how much is read at a time, so a huge file is never in
    /// memory all at once.
    init(chunk: Int = 8 << 20) {
        self.chunk = chunk
    }

    /// Every reply since `since` in `conversations` and their subagents.
    func count(_ conversations: [URL], since: Date) -> [WeightedUse] {
        var uses: [WeightedUse] = []
        var seen: Set<String> = []
        for file in conversations.flatMap(Self.withSubagents) {
            let path = file.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            var state = files[path] ?? FileState()
            read(file, into: &state, since: since)
            state.replies = state.replies.filter { $0.value.at >= since }
            files[path] = state
            uses += state.replies.values.map { WeightedUse(at: $0.at, part: .claudeCode, weight: $0.weight) }
        }
        // Files no longer reported are forgotten.
        files = files.filter { seen.contains($0.key) }
        return uses
    }

    /// A conversation file and its subagents' files,
    /// `<file without .jsonl>/subagents/*.jsonl`.
    static func withSubagents(_ file: URL) -> [URL] {
        let folder = file.deletingPathExtension().appendingPathComponent("subagents")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return [file] + names.filter { $0.hasSuffix(".jsonl") }.sorted().map { folder.appendingPathComponent($0) }
    }

    /// Claude Code's timestamps, with or without fractional seconds.
    static func date(_ stamp: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(stamp))
            ?? (try? Date.ISO8601FormatStyle().parse(stamp))
    }

    /// Lostty's runs since `since`, each weighing every model it used.
    static func uses(of runs: [LosttyRun], since: Date) -> [WeightedUse] {
        runs.filter { $0.at >= since }.map { run in
            WeightedUse(at: run.at, part: .lostty,
                        weight: run.tokens.reduce(0) { $0 + UsageWeights.weight($1.value, model: $1.key) })
        }
    }

    /// Reads `file` past `state.offset`, whole lines only: a half-written
    /// last line waits for next time.
    private func read(_ file: URL, into state: inout FileState, since: Date) {
        // Regular files only: a FIFO named *.jsonl would block the read.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            state = FileState()
            return
        }
        // Not written this week: nothing in it can count.
        if let modified = attributes[.modificationDate] as? Date, modified < since {
            state = FileState()
            return
        }
        // Shorter than what was read: the file was replaced; start over.
        if size < state.offset { state = FileState() }
        guard size > state.offset, let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: state.offset)) != nil else { return }
        var pending = Data()
        while let data = try? handle.read(upToCount: chunk), !data.isEmpty {
            pending.append(data)
            guard let end = pending.lastIndex(of: UInt8(ascii: "\n")) else { continue }
            let lines = pending[pending.startIndex...end]
            Self.parse(lines, into: &state.replies, since: since)
            state.offset += UInt64(lines.count)
            pending = Data(pending[pending.index(after: end)...])
        }
    }

    /// Adds the replies in complete `lines` to `replies`, once each.
    static func parse(_ lines: Data, into replies: inout [String: Reply], since: Date) {
        let usageKey = Data(#""usage""#.utf8)
        for line in lines.split(separator: UInt8(ascii: "\n")) {
            // Most lines are prompts and tool output: skip them before parsing.
            guard line.range(of: usageKey) != nil,
                  let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let id = message["id"] as? String ?? object["uuid"] as? String,
                  let stamp = object["timestamp"] as? String, let at = date(stamp), at >= since
            else { continue }
            func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
            let tokens = TokenCounts(
                input: int("input_tokens"), output: int("output_tokens"),
                cacheWrite: int("cache_creation_input_tokens"), cacheRead: int("cache_read_input_tokens"))
            let weight = UsageWeights.weight(tokens, model: message["model"] as? String ?? "")
            guard weight > 0 else { continue }
            replies[id + "\n" + (object["requestId"] as? String ?? "")] = Reply(at: at, weight: weight)
        }
    }
}
#endif
