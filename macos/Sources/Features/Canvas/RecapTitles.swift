#if os(macOS)
import Foundation

/// Claude Code titles a conversation once, from its first messages, and
/// keeps that title however far the work moves on. Its recaps (`※ recap`)
/// say what the session is about now. Claude Code writes one to the
/// conversation file once you've been away from an idle session for a few
/// minutes, so Lostty watches each Claude pane's file and reads what's
/// added. Each new recap becomes the card's topic, in a few words from
/// Haiku: rules cut half of them badly.
@MainActor
final class RecapTitles {
    static let shared = RecapTitles()
    /// How much of a conversation file's end to look through first.
    nonisolated static let tailBytes = 512 * 1024

    /// Each pane's title from its conversation's latest recap.
    private(set) var titles: [UUID: String] = [:]
    /// A pane's title changed.
    var changed: (UUID) -> Void = { _ in }

    private struct Watch {
        var path: String
        var source: DispatchSourceFileSystemObject
        /// Where reading got to: the end of the last whole line read.
        var offset: UInt64?
        /// The recap the title was made from.
        var titled: String?
        var running = false
        /// The file grew during a look: look once more after it.
        var again = false
    }

    private var watches: [UUID: Watch] = [:]
    private var summarizer: SummarizerKind?

    /// A turn ended in `pane`: from then on its conversation file is
    /// watched for recaps, starting with the latest one already there.
    func turnEnded(pane: UUID, path: String) {
        guard let location = TranscriptLocation.allowed(path), location.agent == .claude else { return }
        let path = location.url.path
        guard watches[pane]?.path != path else { return }
        forget(pane)
        let file = open(path, O_EVTONLY)
        guard file >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: file, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.check(pane) } }
        source.setCancelHandler { close(file) }
        watches[pane] = Watch(path: path, source: source)
        source.resume()
        check(pane)
    }

    /// The pane's conversation ended or the pane closed: its recap is old.
    func forget(_ pane: UUID) {
        guard let watch = watches.removeValue(forKey: pane) else { return }
        watch.source.cancel()
        guard titles.removeValue(forKey: pane) != nil else { return }
        changed(pane)
    }

    private func check(_ pane: UUID) {
        guard var watch = watches[pane] else { return }
        guard !watch.running else {
            watches[pane]?.again = true
            return
        }
        watch.running = true
        watches[pane] = watch
        let (path, offset, titled) = (watch.path, watch.offset, watch.titled)
        Task {
            let kind = await summarizerKind()
            let (read, title) = await Task.detached(priority: .utility) { () -> (RecapRead?, String?) in
                guard let read = Self.readRecap(atPath: path, from: offset) else { return (nil, nil) }
                guard let recap = read.recap, recap != titled else { return (read, nil) }
                return (read, await Self.title(recap, kind: kind))
            }.value
            guard var watch = watches[pane], watch.path == path else { return }
            watch.running = false
            if let read {
                watch.offset = read.end
                if let title {
                    watch.titled = read.recap
                    if titles[pane] != title {
                        titles[pane] = title
                        changed(pane)
                    }
                } else if read.recap.map({ $0 != titled }) == true, kind != .apple, kind != .none {
                    // A lapsed sign-in shows up as a failure: look again at the next recap.
                    summarizer = nil
                }
            }
            let again = watch.again
            watch.again = false
            watches[pane] = watch
            if again { check(pane) }
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

    /// The last recap in what the conversation file added after `offset`
    /// (at first, its last `tailBytes`), without its "(disable recaps in
    /// /config)", and where its last whole line ends.
    nonisolated static func readRecap(atPath path: String, from offset: UInt64?) -> RecapRead? {
        guard let file = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? file.close() }
        guard let end = try? file.seekToEnd() else { return nil }
        // Shorter than where reading got to: rewritten, so read it afresh.
        let from = offset.flatMap { $0 <= end ? $0 : nil }
        let start = from ?? (end > UInt64(tailBytes) ? end - UInt64(tailBytes) : 0)
        try? file.seek(toOffset: start)
        guard var data = try? file.readToEnd() else { return nil }
        // Cut mid-file, the first line (maybe mid-character) is partial: from the next.
        if from == nil, start > 0 { data = data.drop { $0 != UInt8(ascii: "\n") } }
        // A line still being written waits for the next read.
        guard let last = data.lastIndex(of: UInt8(ascii: "\n")) else { return RecapRead(recap: nil, end: start) }
        guard let text = String(bytes: data[...last], encoding: .utf8) else { return nil }
        return RecapRead(recap: latestRecap(in: text), end: start + UInt64(last + 1))
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

/// One read of a conversation file for recaps.
struct RecapRead: Equatable, Sendable {
    var recap: String?
    /// Where the read's last whole line ends.
    var end: UInt64
}
#endif
