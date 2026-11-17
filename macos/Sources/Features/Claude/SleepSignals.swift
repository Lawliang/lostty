#if os(macOS)
import AppKit

/// What sleep needs to know about a pane beyond "its Claude is idle", from
/// the cases where `/exit` hit a terminal still in use: Claude had asked
/// the owner something and was waiting for the answer; another agent's
/// message had just woken it, and more came; or the Mac itself had been
/// asleep, which counted as the pane's idle time.
@MainActor
final class SleepSignals {
    static let shared = SleepSignals()

    /// A card whose last reply asks the owner something waits this long
    /// for the answer before it sleeps, where the setting is shorter.
    static let askingMinutes = 120
    /// A card another agent's message woke stays awake this long: agents
    /// working together write to each other again.
    static let afterWork: TimeInterval = 60 * 60
    /// How much of a conversation file's end is read for the last reply.
    nonisolated static let tailBytes = 256 * 1024

    /// Panes whose last reply ends by asking the owner something.
    private(set) var asksOwner: Set<UUID> = []
    /// When another agent's message last woke each pane.
    private(set) var wokenByWork: [UUID: Date] = [:]
    /// When the Mac last woke from sleep.
    private(set) var macWokeAt: Date?
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.macWokeAt = Date() }
        }
    }

    /// Claude stopped in `pane`: reads the end of its conversation for
    /// whether the reply asks the owner something.
    func turnEnded(_ pane: UUID, transcript path: String) {
        Task.detached(priority: .utility) {
            // The hook fires as Claude stops; its last lines land just after.
            try? await Task.sleep(for: .seconds(1))
            let asks = Self.lastReply(atPath: path).map(Self.asksOwner) ?? false
            await MainActor.run {
                if asks { self.asksOwner.insert(pane) } else { self.asksOwner.remove(pane) }
            }
        }
    }

    /// Claude works again in `pane`, or left it: the question is answered.
    func turnStarted(_ pane: UUID) {
        asksOwner.remove(pane)
    }

    func wokeForWork(_ pane: UUID, now: Date = Date()) {
        wokenByWork[pane] = now
    }

    func closed(_ pane: UUID) {
        asksOwner.remove(pane)
        wokenByWork[pane] = nil
    }

    /// A reply asks the owner something when its last line is a question.
    /// A reply that only reports ends with a statement or a next step.
    nonisolated static func asksOwner(_ reply: String) -> Bool {
        let last = reply.split(whereSeparator: \.isNewline).last { !$0.allSatisfy(\.isWhitespace) }
        guard var line = last?.trimmingCharacters(in: .whitespaces) else { return false }
        // Closing emphasis, quotes and brackets after the question mark.
        while let end = line.last, "*_`\"')]".contains(end) { line.removeLast() }
        return line.hasSuffix("?")
    }

    /// The text of the last reply Claude itself wrote in a conversation
    /// file (not a subagent's), or nil when its end holds none.
    nonisolated static func lastReply(atPath path: String) -> String? {
        guard let file = FileHandle(forReadingAtPath: path), let end = try? file.seekToEnd() else { return nil }
        defer { try? file.close() }
        try? file.seek(toOffset: end > UInt64(tailBytes) ? end - UInt64(tailBytes) : 0)
        guard let data = try? file.readToEnd() else { return nil }
        return lastReply(in: String(decoding: data, as: UTF8.self))
    }

    nonisolated static func lastReply(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline).reversed() where line.contains("\"assistant\"") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "assistant", object["isSidechain"] as? Bool != true,
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }
            let words = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            if let reply = words.last(where: { !$0.allSatisfy(\.isWhitespace) }) { return reply }
        }
        return nil
    }
}
#endif
