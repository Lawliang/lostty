#if os(macOS)
import Foundation

/// What the observer knows about one conversation, in the bubble's order.
/// No list has a length limit.
struct ObserverNotes: Encodable, Equatable, Sendable {
    /// Why the session started, in a sentence or two.
    var why = ""
    /// What the developer asked for.
    var asked: [String] = []
    /// What the developer and the agent decided together.
    var decided: [String] = []
    /// What's done and working.
    var built: [String] = []
    /// How far along, in a few words ("about two-thirds done"); empty when unclear.
    var progress = ""
    /// What's still to do, and anything waiting on the developer.
    var left: [String] = []
    /// The agent's last reply in plain words.
    var justNow: String

    enum CodingKeys: String, CodingKey {
        case why, asked, decided, built, progress, left
        case justNow = "just_now"
    }
}

/// The prompt for one observer run, and reading its JSON reply (spec §4).
enum ObserverPrompt {
    /// The most words a Claude or Codex run carries.
    static let cliWords = 30_000
    /// Apple's on-device model reads about 4,000 tokens.
    static let appleWords = 1_500

    /// `previous`: the notes so far. `earlier`: what's new since they were
    /// written, up to and including your latest prompt. `lastReply`: the
    /// agent's text since that prompt. The reply gets up to half of
    /// `words`; the newest of `earlier` gets the rest.
    static func build(previous: ObserverNotes?, earlier: [ConversationEntry], lastReply: String, words: Int) -> String {
        let reply = keepingNewest(lastReply, words: words / 2)
        let context = cut(earlier, toWords: words - wordCount(reply))
        let notes = previous.flatMap(json) ?? "(none yet)"
        let conversation = context.isEmpty ? "(nothing new)" : context.map {
            ($0.speaker == .you ? "You: " : "Agent: ") + $0.text
        }.joined(separator: "\n\n")
        return """
        You keep notes on a coding session in a terminal, for the developer running it. Call the developer \
        "you", and the developer and the agent together "we". Below are your notes so far (JSON), the \
        conversation since then (the developer's prompts and the coding agent's replies, with tool calls left \
        out), and the agent's last reply.

        Answer with JSON only, no code fence:
        {"why": "…", "asked": ["…"], "decided": ["…"], "built": ["…"], "progress": "…", "left": ["…"], "just_now": "…"}
        - why: why the developer started this session, in a sentence or two.
        - asked: what they asked for, one short bullet each.
        - decided: what we decided together, one bullet each. Start a bullet with a short label and a colon \
        when that helps ("Look: …").
        - built: what's done and working, one bullet each.
        - progress: how far along the work is, in a few words ("about two-thirds done"), or "" when unclear.
        - left: what's still to do, and anything waiting on the developer.
        - just_now: the agent's last reply explained like the developer is five: plain words, short sentences, \
        what it means for them, and anything it needs from them.
        Keep what your notes say unless the conversation changed it, and add what's new. Merge or reword \
        bullets only when that makes a list clearer. No length limits. Leave a list empty when nothing fits it.

        Your notes so far:
        \(notes)

        Conversation since then:
        \(conversation)

        The agent's last reply:
        \(reply.isEmpty ? "(none)" : reply)
        """
    }

    /// The notes in a reply, which may be wrapped in a code fence or follow
    /// a sentence. Missing keys are empty; nil when it isn't a JSON object,
    /// a key has the wrong type, or `just_now` is empty.
    static func parse(_ reply: String) -> ObserverNotes? {
        guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
              let wire = try? JSONDecoder().decode(Wire.self, from: Data(reply[open...close].utf8)),
              let justNow = wire.justNow.map(trimmed), !justNow.isEmpty else { return nil }
        func list(_ items: [String]?) -> [String] { (items ?? []).map(bullet).filter { !$0.isEmpty } }
        return ObserverNotes(
            why: trimmed(wire.why ?? ""), asked: list(wire.asked), decided: list(wire.decided),
            built: list(wire.built), progress: trimmed(wire.progress ?? ""), left: list(wire.left),
            justNow: justNow)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private struct Wire: Decodable {
        var why, progress, justNow: String?
        var asked, decided, built, left: [String]?

        enum CodingKeys: String, CodingKey {
            case why, asked, decided, built, progress, left
            case justNow = "just_now"
        }
    }

    /// Compact, sorted JSON, so the model sees its own format back.
    private static func json(_ notes: ObserverNotes) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(notes)).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A bullet without the list marker a model sometimes adds.
    private static func bullet(_ text: String) -> String {
        var line = trimmed(text)
        for marker in ["- ", "• ", "* "] where line.hasPrefix(marker) {
            line = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    /// The newest entries that fit in `words`; one that straddles the cut
    /// keeps its end, after "… ".
    private static func cut(_ entries: [ConversationEntry], toWords words: Int) -> [ConversationEntry] {
        var kept: [ConversationEntry] = []
        var room = words
        for entry in entries.reversed() {
            guard room > 0 else { break }
            let count = wordCount(entry.text)
            if count <= room {
                kept.append(entry)
                room -= count
            } else {
                kept.append(ConversationEntry(speaker: entry.speaker, text: keepingNewest(entry.text, words: room)))
                room = 0
            }
        }
        return kept.reversed()
    }

    /// `text` if it has at most `words` words; otherwise "… " and its last
    /// `words` words.
    private static func keepingNewest(_ text: String, words: Int) -> String {
        let all = text.split(whereSeparator: \.isWhitespace)
        guard all.count > words else { return text }
        guard words > 0 else { return "" }
        return "… " + all.suffix(words).joined(separator: " ")
    }
}
#endif
