#if os(macOS)
import AppKit
import Combine
import Foundation

/// A terminal whose agent finished a request while you weren't looking:
/// one temporary notification, under the regular ones.
struct TerminalNotice: Identifiable, Equatable {
    let id = UUID()
    let pane: UUID
    /// The pane's title, without the agent's ✳.
    var title: String
    var project: ProjectLabel?
    var recap: RequestRecap
}

/// Temporary notifications: a pane's agent finished a request while the
/// pane wasn't focused ("Ready for response", `ClaudeRuntime.awaiting`).
/// Each shows in full, then collapses into a dimmed stack `lifetime`
/// seconds later; hovering keeps it open. It goes when its pane leaves
/// awaiting: focused, prompted again, or closed. Newest first.
@MainActor
final class TerminalNotices: ObservableObject {
    typealias Scheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    static let shared = TerminalNotices()
    static let lifetime: TimeInterval = 4

    @Published private(set) var items: [TerminalNotice] = []
    @Published private(set) var collapsed: Set<UUID> = []

    private let schedule: Scheduler
    private var hovering: Set<UUID> = []
    private var generation: [UUID: Int] = [:]
    private var awaiting: Set<UUID> = []
    private var watch: AnyCancellable?

    init(schedule: @escaping Scheduler = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }) {
        self.schedule = schedule
    }

    /// Follows which panes await a response. Once, at launch.
    func start() {
        watch = ClaudeRuntime.shared.$awaiting.sink { [weak self] in self?.awaitingChanged($0) }
    }

    /// A pane's request ended (`ClaudeRuntime.requestEnded`): when the pane
    /// awaits a response, its notice, once its conversation names the
    /// request and the reply.
    func requestEnded(pane: UUID, path: String, since: Date) {
        guard awaiting.contains(pane), let surface = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: pane) else { return }
        let title = Self.title(surface.title)
        let pwd = SkinsRuntime.shared.manager.panes[pane]?.pwd
        // Codex words its conversation another way.
        let conversation = TranscriptLocation.allowed(path).flatMap { $0.agent == .claude ? $0.url : nil }
        Task {
            let (project, recap) = await Task.detached(priority: .utility) {
                var recap = RequestRecap()
                if let conversation { recap = await RequestRecap.read(conversation, since: since) }
                return (pwd.flatMap { ProjectLabel.read(pwd: $0) }, recap)
            }.value
            post(TerminalNotice(pane: pane, title: title, project: project, recap: recap))
        }
    }

    /// The pane's notice replaces any it had, while it still awaits.
    func post(_ notice: TerminalNotice) {
        guard awaiting.contains(notice.pane) else { return }
        for old in items where old.pane == notice.pane { forget(old.id) }
        items.removeAll { $0.pane == notice.pane }
        items.insert(notice, at: 0)
        countdown(notice.id)
    }

    func awaitingChanged(_ panes: Set<UUID>) {
        awaiting = panes
        for item in items where !panes.contains(item.pane) { forget(item.id) }
        items.removeAll { !panes.contains($0.pane) }
    }

    func setHovering(_ id: UUID, _ isHovering: Bool) {
        if isHovering {
            hovering.insert(id)
        } else {
            hovering.remove(id)
            if !collapsed.contains(id) { countdown(id) }
        }
    }

    /// Tapping a notice: its pane, focused, centered on the canvas.
    func open(_ notice: TerminalNotice) {
        guard let surface = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: notice.pane) else { return }
        let controllers: [BaseTerminalController] = TerminalController.all + CanvasController.allCards
        guard let controller = controllers.first(where: { $0.surfaceTree.contains(surface) }) else { return }
        if let card = controller as? CardController { card.canvas?.zoom(to: card) }
        controller.focusSurface(surface)
    }

    /// "✳ Fix the login" → "Fix the login".
    static func title(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.unicodeScalars.first,
              first == "✳" || ClaudeRuntime.isSpinner(trimmed) else { return trimmed }
        return String(trimmed.unicodeScalars.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private func countdown(_ id: UUID) {
        let token = (generation[id] ?? 0) + 1
        generation[id] = token
        schedule(Self.lifetime) { [weak self] in
            guard let self, self.generation[id] == token, !self.hovering.contains(id),
                  self.items.contains(where: { $0.id == id }) else { return }
            self.collapsed.insert(id)
        }
    }

    private func forget(_ id: UUID) {
        collapsed.remove(id)
        hovering.remove(id)
        generation[id] = nil
    }
}

/// The request an agent just finished, from its conversation file: the
/// first line of the owner's message that began it, and of the agent's
/// last reply.
struct RequestRecap: Equatable, Sendable {
    var request: String?
    var reply: String?

    /// Claude Code writes the last reply after its Stop hook starts, then a
    /// `stop_hook_summary` line: the file's end is read until that line
    /// shows, for about three seconds at most.
    static func read(_ url: URL, since: Date, tail: Int = 4 << 20, tries: Int = 15) async -> RequestRecap {
        var recap = RequestRecap()
        for attempt in 0...tries {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(200)) }
            let lines = lastLines(url, tail: tail)
            recap = from(lines)
            if lines.contains(where: { isStop($0, since: since) }) { break }
        }
        return recap
    }

    /// From a conversation's lines, oldest first: the last message the
    /// owner typed, and the agent's last words after it.
    static func from(_ lines: [Data]) -> RequestRecap {
        var recap = RequestRecap()
        for line in lines {
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let message = object["message"] as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "user":
                guard object["isMeta"] as? Bool != true, object["isCompactSummary"] as? Bool != true,
                      let text = typed(message["content"]) else { continue }
                recap = RequestRecap(request: text)
            case "assistant":
                let blocks = message["content"] as? [[String: Any]] ?? []
                if let text = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String,
                   let line = firstLine(text) {
                    recap.reply = line
                }
            default: continue
            }
        }
        return recap
    }

    /// A user line's first line when the owner typed it: not a tool's
    /// result, a command's output, or a notice Claude Code adds.
    private static func typed(_ content: Any?) -> String? {
        let text: String?
        if let string = content as? String {
            text = string
        } else if let blocks = content as? [[String: Any]], !blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
            text = blocks.first { $0["type"] as? String == "text" }?["text"] as? String
        } else {
            text = nil
        }
        guard let text, let line = firstLine(text), !line.hasPrefix("<"), !line.hasPrefix("[Request interrupted") else {
            return nil
        }
        return line
    }

    private static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    private static let stopKey = Data(#""stop_hook_summary""#.utf8)

    private static func isStop(_ line: Data, since: Date) -> Bool {
        guard line.range(of: stopKey) != nil,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["subtype"] as? String == "stop_hook_summary",
              let stamp = object["timestamp"] as? String, let at = UsageCounter.date(stamp) else { return false }
        return at >= since
    }

    /// The whole lines in the last `tail` bytes of a regular file.
    private static func lastLines(_ url: URL, tail: Int) -> [Data] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let start = max(0, size - tail)
        guard (try? handle.seek(toOffset: UInt64(start))) != nil, let data = try? handle.readToEnd() else { return [] }
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines.map { Data($0) }
    }
}
#endif
