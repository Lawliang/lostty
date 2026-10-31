#if os(macOS)
import Foundation

/// Claude Code titles a conversation once, from its first messages, and
/// keeps that title however far the work moves on. Its recaps (`※ recap`,
/// written to the conversation file about three minutes into an idle wait)
/// say what the session is about now. Each new recap becomes the card's
/// topic, in a few words from Haiku: rules cut half of them badly.
@MainActor
final class RecapTitles {
    static let shared = RecapTitles()
    /// How long after a turn's end to look for its recap: Claude Code
    /// writes one about 3 minutes into the wait.
    static let recapWait: TimeInterval = 200
    /// How much of the end of a conversation file to look through.
    nonisolated static let tailBytes = 512 * 1024

    /// Each pane's title from its conversation's latest recap.
    private(set) var titles: [UUID: String] = [:]
    /// A pane's title changed.
    var changed: (UUID) -> Void = { _ in }

    private var paths: [UUID: String] = [:]
    /// The recap each pane's title was made from.
    private var titled: [UUID: String] = [:]
    private var checks: [UUID: DispatchWorkItem] = [:]
    private var running: Set<UUID> = []
    private var summarizer: SummarizerKind?

    /// A turn ended in `pane`: look for a recap now (one that came while
    /// you were away) and again once this wait's would have come.
    func turnEnded(pane: UUID, path: String) {
        guard let location = TranscriptLocation.allowed(path), location.agent == .claude else { return }
        if paths[pane] != location.url.path {
            paths[pane] = location.url.path
            forgetTitle(pane)
        }
        check(pane)
        checks[pane]?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.check(pane) } }
        checks[pane] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recapWait, execute: work)
    }

    /// The pane's conversation ended or the pane closed: its recap is old.
    func forget(_ pane: UUID) {
        checks.removeValue(forKey: pane)?.cancel()
        paths[pane] = nil
        forgetTitle(pane)
    }

    private func forgetTitle(_ pane: UUID) {
        titled[pane] = nil
        guard titles.removeValue(forKey: pane) != nil else { return }
        changed(pane)
    }

    private func check(_ pane: UUID) {
        guard let path = paths[pane], !running.contains(pane) else { return }
        running.insert(pane)
        let titled = titled[pane]
        Task {
            let kind = await summarizerKind()
            let made = await Task.detached(priority: .utility) { () -> (String, String?)? in
                guard let recap = Self.latestRecap(atPath: path), recap != titled else { return nil }
                return (recap, await Self.title(recap, kind: kind))
            }.value
            running.remove(pane)
            guard let (recap, title) = made, paths[pane] == path else { return }
            guard let title else {
                // A lapsed sign-in shows up as a failure: look again next time.
                summarizer = nil
                return
            }
            self.titled[pane] = recap
            guard titles[pane] != title else { return }
            titles[pane] = title
            changed(pane)
        }
    }

    private func summarizerKind() async -> SummarizerKind {
        if let summarizer { return summarizer }
        let kind = await Task.detached(priority: .utility) { Summarizer.detect() }.value
        summarizer = kind
        return kind
    }

    /// Haiku (or Codex) names the recap's work. Apple's on-device model
    /// answers with chatter and lists, so it makes none.
    nonisolated static func title(_ recap: String, kind: SummarizerKind) async -> String? {
        switch kind {
        case .claude, .codex:
            guard case .success(let answer) = await Summarizer.run(kind, prompt: prompt(recap), handle: RunHandle()) else {
                return nil
            }
            return clean(answer)
        case .apple, .none:
            return nil
        }
    }

    nonisolated static func prompt(_ recap: String) -> String {
        """
        Title this terminal tab from the coding-session recap below. Reply with only the title: 2 to 5 words \
        naming the feature or project the session is about. Ignore the "Next" part, and leave out status words \
        like merged, done, installed, fix, recap or pending, sentence case, no quotes or period.

        \(recap)
        """
    }

    /// The answer's first line, without quotes or a closing period; nil
    /// when it's empty or too long to be a title.
    nonisolated static func clean(_ answer: String) -> String? {
        let line = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let title = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`*. ").union(.whitespaces))
        let words = title.split(separator: " ").count
        return (1...8).contains(words) ? title : nil
    }

    /// The last recap in the conversation file's last `tailBytes`, without
    /// its "(disable recaps in /config)".
    nonisolated static func latestRecap(atPath path: String) -> String? {
        guard let file = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? file.close() }
        guard let end = try? file.seekToEnd() else { return nil }
        let start = end > UInt64(tailBytes) ? end - UInt64(tailBytes) : 0
        try? file.seek(toOffset: start)
        guard var data = try? file.readToEnd() else { return nil }
        // Mid-file, the first line (maybe mid-character) is cut: from the next.
        if start > 0 { data = data.drop { $0 != UInt8(ascii: "\n") } }
        guard let text = String(bytes: data, encoding: .utf8) else { return nil }
        return latestRecap(in: text)
    }

    nonisolated static func latestRecap(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline).reversed() where line.contains("\"away_summary\"") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["subtype"] as? String == "away_summary",
                  let content = object["content"] as? String else { continue }
            let recap = content.replacingOccurrences(of: "(disable recaps in /config)", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !recap.isEmpty { return recap }
        }
        return nil
    }
}
#endif
