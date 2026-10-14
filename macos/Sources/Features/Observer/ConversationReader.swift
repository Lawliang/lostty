#if os(macOS)
import Foundation

/// One prompt you typed, or the agent's text for a stretch of its turn.
struct ConversationEntry: Equatable, Sendable {
    enum Speaker: Equatable, Sendable {
        case you, agent
    }

    var speaker: Speaker
    var text: String
}

/// What a read found past an offset.
struct ConversationChunk: Equatable, Sendable {
    var entries: [ConversationEntry]
    /// Where the next read starts: just past the last whole line.
    var offset: UInt64
    /// The file was shorter than the offset asked for (it was rewritten),
    /// so this chunk reads it from the start.
    var restarted: Bool
}

/// Turns a Claude Code or Codex conversation file (JSONL) into your prompts
/// and the agent's replies, without tool calls, tool output, thinking,
/// subagents or the agents' own context (spec §3).
enum ConversationReader {
    /// The entries in `data`'s whole lines, and how many bytes those lines
    /// take; a half-written last line is left for the next read.
    static func parse(_ data: Data, agent: TranscriptAgent) -> (entries: [ConversationEntry], consumed: Int) {
        var entries: [ConversationEntry] = []
        var start = data.startIndex
        var consumed = 0
        while let newline = data[start...].firstIndex(of: 0x0A) {
            let line = data[start..<newline]
            start = data.index(after: newline)
            consumed = start - data.startIndex
            guard !line.isEmpty,
                  let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let entry = agent == .claude ? claudeEntry(object) : codexEntry(object) else { continue }
            append([entry], to: &entries)
        }
        return (entries, consumed)
    }

    /// The entries after `offset` in a regular file; nil when it can't be
    /// read (or isn't a regular file: a FIFO would block).
    static func read(_ location: TranscriptLocation, from offset: UInt64) -> ConversationChunk? {
        let path = location.url.path
        guard let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType,
              type == .typeRegular,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let restarted = end < offset
        let start = restarted ? 0 : offset
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        let data = (try? handle.readToEnd()) ?? Data()
        let parsed = parse(data, agent: location.agent)
        return ConversationChunk(entries: parsed.entries, offset: start + UInt64(parsed.consumed), restarted: restarted)
    }

    /// Appends `new`, joining the agent's consecutive stretches (text, tool
    /// calls, more text) into one entry.
    static func append(_ new: [ConversationEntry], to entries: inout [ConversationEntry]) {
        for entry in new {
            if entry.speaker == .agent, let last = entries.last, last.speaker == .agent {
                entries[entries.count - 1].text = last.text + "\n\n" + entry.text
            } else {
                entries.append(entry)
            }
        }
    }

    /// Your latest prompt and everything after it, given the last tail and
    /// what's new. Without a prompt in `new`, the reply carries on.
    static func tail(_ tail: [ConversationEntry], adding new: [ConversationEntry]) -> [ConversationEntry] {
        if let index = new.lastIndex(where: { $0.speaker == .you }) { return Array(new[index...]) }
        var result = tail
        append(new, to: &result)
        return result
    }

    /// The agent's text after your latest prompt.
    static func lastReply(_ tail: [ConversationEntry]) -> String {
        tail.filter { $0.speaker == .agent }.map(\.text).joined(separator: "\n\n")
    }

    // MARK: - Claude Code

    private static func claudeEntry(_ object: [String: Any]) -> ConversationEntry? {
        guard object["isSidechain"] as? Bool != true, object["isMeta"] as? Bool != true,
              object["isCompactSummary"] as? Bool != true,
              let message = object["message"] as? [String: Any] else { return nil }
        switch object["type"] as? String {
        case "user":
            let raw: String
            if let text = message["content"] as? String {
                raw = text
            } else if let items = message["content"] as? [[String: Any]],
                      !items.contains(where: { $0["type"] as? String == "tool_result" }) {
                // A prompt with an image: its text items.
                raw = texts(items, type: "text").joined(separator: "\n")
            } else {
                return nil
            }
            let text = withoutReminders(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isWrapper(text) else { return nil }
            return ConversationEntry(speaker: .you, text: text)
        case "assistant":
            guard let items = message["content"] as? [[String: Any]] else { return nil }
            let text = texts(items, type: "text").joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : ConversationEntry(speaker: .agent, text: text)
        default:
            return nil
        }
    }

    /// `<system-reminder>…</system-reminder>` blocks Claude Code adds to prompts.
    private static func withoutReminders(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<system-reminder>"),
              let close = result.range(of: "</system-reminder>", range: open.upperBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result
    }

    // MARK: - Codex

    private static func codexEntry(_ object: [String: Any]) -> ConversationEntry? {
        guard object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              let items = payload["content"] as? [[String: Any]] else { return nil }
        switch payload["role"] as? String {
        case "user":
            let text = texts(items, type: "input_text")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !isWrapper($0) }
                .joined(separator: "\n")
            return text.isEmpty ? nil : ConversationEntry(speaker: .you, text: text)
        case "assistant":
            let text = texts(items, type: "output_text").joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : ConversationEntry(speaker: .agent, text: text)
        default:
            return nil
        }
    }

    // MARK: - Shared

    private static func texts(_ items: [[String: Any]], type: String) -> [String] {
        items.compactMap { $0["type"] as? String == type ? $0["text"] as? String : nil }
    }

    /// Text the agent's program wrote into the user's turn, not a prompt:
    /// a leading tag (`<command-name>`, `<bash-input>`, `<task-notification>`,
    /// Codex's `<environment_context>`) or Codex's AGENTS.md block.
    static func isWrapper(_ text: String) -> Bool {
        text.range(of: #"^<[a-z][a-z0-9_-]*>"#, options: .regularExpression) != nil
            || text.hasPrefix("# AGENTS.md instructions")
    }
}
#endif
