#if os(macOS)
import Foundation

/// Sums one request's tokens, unweighted: every reply in a conversation
/// file and its subagents' files since the request began. An actor, so
/// reading runs off the main thread; it remembers how far it read each
/// file, so the next request reads only what was added.
actor RequestTokens {
    private var offsets: [String: UInt64] = [:]
    private let chunk: Int
    private let tail: UInt64
    private let settle: Duration
    private let tries: Int

    /// `tail`: how far back from the end a file never read before starts.
    /// Conversation files grow past 100 MB, and a request is at the end.
    /// `settle`, `tries`: how often and how many times to look again for
    /// the conversation's record that the Stop hooks ran.
    init(chunk: Int = 8 << 20, tail: UInt64 = 32 << 20, settle: Duration = .milliseconds(200), tries: Int = 15) {
        self.chunk = chunk
        self.tail = tail
        self.settle = settle
        self.tries = tries
    }

    /// Claude Code writes the request's replies after its Stop hook starts
    /// (the hook that reports the request's end), then a
    /// `stop_hook_summary` line once the hooks ran: the conversation is
    /// read until that line, for a few seconds at most.
    func total(_ conversation: URL, since: Date) async -> Int {
        var seen: Set<String> = []
        var tokens = 0
        for attempt in 0...tries {
            if attempt > 0 { try? await Task.sleep(for: settle) }
            let pass = read(conversation, since: since, seen: &seen)
            tokens += pass.tokens
            if pass.stopped { break }
        }
        return UsageCounter.withSubagents(conversation).dropFirst().reduce(tokens) {
            $0 + read($1, since: since, seen: &seen).tokens
        }
    }

    /// The tokens of the replies since `since` in what `file` added, whole
    /// lines only, each reply once by its key in `seen`, and whether a Stop
    /// since then was recorded.
    private func read(_ file: URL, since: Date, seen: inout Set<String>) -> (tokens: Int, stopped: Bool) {
        // Regular files only: a FIFO named *.jsonl would block the read.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date, modified >= since
        else { return (0, false) }
        let path = file.path
        // Shorter than what was read: the file was replaced; start over.
        if let known = offsets[path], known > size { offsets[path] = nil }
        var offset: UInt64
        var midLine = false
        if let known = offsets[path] {
            offset = known
        } else {
            // One byte early, so a start on a line's first byte drops only
            // the newline before it.
            offset = size > tail ? size - tail - 1 : 0
            midLine = offset > 0
        }
        defer { offsets[path] = offset }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: file) else { return (0, false) }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil else { return (0, false) }
        let newline = UInt8(ascii: "\n")
        var tokens = 0
        var stopped = false
        var pending = Data()
        while let data = try? handle.read(upToCount: chunk), !data.isEmpty {
            pending.append(data)
            if midLine {
                guard let first = pending.firstIndex(of: newline) else { continue }
                offset += UInt64(pending.distance(from: pending.startIndex, to: first) + 1)
                pending = Data(pending[pending.index(after: first)...])
                midLine = false
            }
            guard let end = pending.lastIndex(of: newline) else { continue }
            let lines = pending[pending.startIndex...end]
            for line in lines.split(separator: newline) {
                if !stopped, Self.isStop(line, since: since) { stopped = true }
                guard let reply = AssistantReply(line), reply.at >= since, seen.insert(reply.key).inserted
                else { continue }
                tokens += reply.tokens.total
            }
            offset += UInt64(lines.count)
            pending = Data(pending[pending.index(after: end)...])
        }
        return (tokens, stopped)
    }

    private static let stopKey = Data(#""stop_hook_summary""#.utf8)

    private static func isStop(_ line: Data, since: Date) -> Bool {
        guard line.range(of: stopKey) != nil,
              let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
              object["subtype"] as? String == "stop_hook_summary",
              let stamp = object["timestamp"] as? String, let at = UsageCounter.date(stamp)
        else { return false }
        return at >= since
    }
}
#endif
