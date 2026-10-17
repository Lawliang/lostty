#if os(macOS)
import Foundation

/// The agent's reply since your latest prompt, from the end of its
/// conversation file: where a handoff block is.
enum ContextHandoffReply {
    /// How much of the file's end is read.
    static let window = 1 << 20

    /// For a conversation file a hook named (TranscriptLocation decides).
    static func last(_ path: String) -> String? {
        guard let location = TranscriptLocation.allowed(path) else { return nil }
        return last(in: location.url, agent: location.agent)
    }

    static func last(in url: URL, agent: TranscriptAgent) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(window) ? end - UInt64(window) : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        var data = (try? handle.readToEnd()) ?? Data()
        // Mid-file: the first line is cut, so start at the next one.
        if start > 0, let newline = data.firstIndex(of: 0x0A) { data = Data(data[data.index(after: newline)...]) }
        let entries = ConversationReader.parse(data, agent: agent).entries
        return ConversationReader.lastReply(ConversationReader.tail([], adding: entries))
    }
}
#endif
