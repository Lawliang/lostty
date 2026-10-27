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

    /// `tail`: how far back from the end a file never read before starts.
    /// Conversation files grow past 100 MB, and a request is at the end.
    init(chunk: Int = 8 << 20, tail: UInt64 = 32 << 20) {
        self.chunk = chunk
        self.tail = tail
    }

    func total(_ conversation: URL, since: Date) -> Int {
        var seen: Set<String> = []
        return UsageCounter.withSubagents(conversation).reduce(0) { $0 + read($1, since: since, seen: &seen) }
    }

    /// The tokens of the replies since `since` in what `file` added, whole
    /// lines only, each reply once by its key in `seen`.
    private func read(_ file: URL, since: Date, seen: inout Set<String>) -> Int {
        // Regular files only: a FIFO named *.jsonl would block the read.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date, modified >= since
        else { return 0 }
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
        guard size > offset, let handle = try? FileHandle(forReadingFrom: file) else { return 0 }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil else { return 0 }
        let newline = UInt8(ascii: "\n")
        var tokens = 0
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
                guard let reply = AssistantReply(line), reply.at >= since, seen.insert(reply.key).inserted
                else { continue }
                tokens += reply.tokens.total
            }
            offset += UInt64(lines.count)
            pending = Data(pending[pending.index(after: end)...])
        }
        return tokens
    }
}
#endif
