import Foundation

/// Claude Code's working line, as it shows under the conversation:
/// `✳ Incubating… (3m 51s · ↓ 23.5k tokens)`. Read from the pane when the
/// sessions were listed (`seenAt`); the phone draws its own glyph and lets
/// the time run on from there.
public struct ClaudeSpinner: Equatable, Sendable {
    /// The glyphs Claude cycles through, there and back.
    public static let glyphs = ["·", "✢", "✳", "✶", "✻", "✽"]

    /// "Incubating…".
    public var word: String
    /// How long Claude has worked on this turn, when the line said.
    public var elapsed: TimeInterval?
    /// The rest of the parentheses: "↓ 23.5k tokens".
    public var detail: String?
    public var seenAt: Date

    public init(word: String, elapsed: TimeInterval? = nil, detail: String? = nil, seenAt: Date) {
        self.word = word
        self.elapsed = elapsed
        self.detail = detail
        self.seenAt = seenAt
    }

    /// Reads a line the list script took from the pane; nil when it isn't
    /// Claude's working line.
    public init?(line: String, seenAt: Date) {
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        guard let glyph = Self.glyphs.first(where: { rest.hasPrefix($0 + " ") }) else { return nil }
        rest = rest.dropFirst(glyph.count + 1)
        var inside: Substring = ""
        if let open = rest.range(of: " ("), rest.hasSuffix(")") {
            inside = rest[open.upperBound..<rest.index(before: rest.endIndex)]
            rest = rest[..<open.lowerBound]
        }
        let word = rest.trimmingCharacters(in: .whitespaces)
        guard word.hasSuffix("…"), word.count > 1 else { return nil }
        var parts = inside.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }
        let elapsed = parts.first.flatMap(Self.duration)
        if elapsed != nil { parts.removeFirst() }
        // How to stop it is no use on the phone.
        parts.removeAll { $0.isEmpty || $0.contains("esc to") }
        self.init(
            word: word, elapsed: elapsed, detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
            seenAt: seenAt)
    }

    /// "(3m 51s · ↓ 23.5k tokens)" as of `now`, the time running on since
    /// the line was read; just "(3m 51s)" without `detail`; nil when there
    /// is nothing to say.
    public func parentheses(now: Date, detail withDetail: Bool = true) -> String? {
        let time = elapsed.map { Self.format($0 + max(0, now.timeIntervalSince(seenAt))) }
        let parts = [time, withDetail ? detail : nil].compactMap { $0 }
        return parts.isEmpty ? nil : "(\(parts.joined(separator: " · ")))"
    }

    /// The glyph `Claude` would show `ticks` frames in: up the list and
    /// back down again.
    public static func glyph(tick: Int) -> String {
        let cycle = glyphs + glyphs.dropFirst().dropLast().reversed()
        return cycle[((tick % cycle.count) + cycle.count) % cycle.count]
    }

    /// "25s", "3m 51s", "1h 2m 3s" → seconds; nil for anything else.
    static func duration(_ text: String) -> TimeInterval? {
        let units: [Character: TimeInterval] = ["h": 3600, "m": 60, "s": 1]
        var total: TimeInterval = 0
        let words = text.split(separator: " ")
        guard !words.isEmpty else { return nil }
        for word in words {
            guard let unit = word.last, let scale = units[unit], let n = Int(word.dropLast()) else { return nil }
            total += TimeInterval(n) * scale
        }
        return total
    }

    /// Seconds as Claude writes them: "25s", "3m 51s", "1h 2m 3s".
    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m \(s % 60)s"
    }
}
