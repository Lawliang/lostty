#if os(macOS)
import Foundation

/// One line of a subagent's or background shell's feed.
struct FeedLine: Equatable, Identifiable, Sendable {
    enum Style: Equatable, Sendable {
        /// The subagent's brief, dimmed.
        case brief
        /// What a tool call does: "▸ Reading Foo.swift".
        case action
        /// A failed tool call's first line.
        case failed
        /// The subagent's own words, a message from Claude, or shell output.
        case words
        /// "✓ Done".
        case done
    }

    let id: Int
    let text: String
    let style: Style
}

/// What a task's file holds now: its last lines, and for a subagent the
/// task Claude gave it.
struct TaskFeedEntry: Equatable, Sendable {
    var lines: [FeedLine] = []
    var caption: String?
}

/// A subagent's transcript or a shell's output file, as lines. The
/// transcript is Claude Code's own JSONL, worded as `+agent-watch` words it
/// (feed.zig); its format isn't a documented API, so lines this doesn't
/// know show nothing rather than fail.
enum TaskFeed {
    /// How much of the file's end is read.
    static let tail = 512 << 10

    /// Its last `limit` lines; nil when the file can't be read.
    static func read(_ task: PaneTask, limit: Int) -> TaskFeedEntry? {
        guard let path = task.readablePath(), let data = tailData(path) else { return nil }
        switch task.kind {
        case .subagent:
            let lines = data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
            return TaskFeedEntry(lines: numbered(subagent(lines).suffix(limit)), caption: caption(path))
        case .shell:
            return TaskFeedEntry(lines: numbered(shell(data).suffix(limit).map { ($0, .words) }))
        }
    }

    /// When the file last changed, so an unchanged one isn't read again.
    static func stamp(_ task: PaneTask) -> Date? {
        guard let path = task.readablePath(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    /// A subagent's transcript lines, oldest first, as feed lines.
    static func subagent(_ lines: [Data]) -> [(String, FeedLine.Style)] {
        var out: [(String, FeedLine.Style)] = []
        for line in lines {
            guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let kind = root["type"] as? String, let message = root["message"] as? [String: Any],
                  let content = message["content"] else { continue }
            if kind == "user" {
                // The first line is the brief; a later one is Claude's follow-up.
                let brief = root["parentUuid"] == nil || root["parentUuid"] is NSNull
                if let text = content as? String {
                    out += words(text, brief: brief)
                    continue
                }
                for block in content as? [[String: Any]] ?? [] {
                    switch block["type"] as? String {
                    case "text":
                        out += words(block["text"] as? String ?? "", brief: brief)
                    case "tool_result" where block["is_error"] as? Bool == true:
                        out.append(("✗ " + firstLine(resultText(block["content"]) ?? "failed"), .failed))
                    default:
                        continue
                    }
                }
            } else if kind == "assistant" {
                for block in content as? [[String: Any]] ?? [] {
                    switch block["type"] as? String {
                    case "tool_use":
                        guard let name = block["name"] as? String else { continue }
                        let input = block["input"] as? [String: Any] ?? [:]
                        // Its report, handed back through a tool.
                        if name == "SubagentHandback" {
                            out += words(input["message"] as? String ?? "", brief: false, from: nil)
                        } else {
                            out.append(("▸ " + action(name, input), .action))
                        }
                    case "text":
                        out += words(block["text"] as? String ?? "", brief: false, from: nil)
                    default:
                        continue
                    }
                }
                if message["stop_reason"] as? String == "end_turn" { out.append(("✓ Done", .done)) }
            }
        }
        return out
    }

    /// A shell's output as lines: escape sequences and control characters
    /// dropped, and a line a progress bar rewrote with "\r" shown as it
    /// ended up.
    static func shell(_ data: Data) -> [String] {
        // Output that isn't UTF-8 still shows, a byte a character.
        let text = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
        var lines = text.components(separatedBy: "\n").map { line in
            printable(String(line.split(separator: "\r", omittingEmptySubsequences: false).last(where: { !$0.isEmpty }) ?? ""))
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines
    }

    /// What a tool call does, as a person reads it at a glance (protocol.zig's
    /// toolAction): "Editing Foo.swift", "Searching for \"bar\"", or the
    /// description Claude gave a shell command.
    static func action(_ tool: String, _ input: [String: Any]) -> String {
        func field(_ key: String) -> String? {
            guard let value = input[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return firstLine(value)
        }
        let file = { (path: String) in (path as NSString).lastPathComponent }
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            if let path = field("file_path") ?? field("notebook_path") { return "Editing " + file(path) }
        case "Read":
            if let path = field("file_path") { return "Reading " + file(path) }
        case "Grep", "Glob":
            if let pattern = field("pattern") { return "Searching for \"\(pattern)\"" }
        case "WebSearch":
            if let query = field("query") { return "Searching for \"\(query)\"" }
        case "WebFetch":
            if let url = field("url") { return "Reading " + (URL(string: url)?.host ?? url) }
        case "Bash":
            if let words = field("description") ?? field("command") { return words }
        case "Task", "Agent":
            if let description = field("description") { return "Agent: " + description }
        default:
            break
        }
        // An MCP tool ("mcp__server__tool") by its own name.
        if tool.hasPrefix("mcp__"), let range = tool.range(of: "__", options: .backwards), range.upperBound < tool.endIndex {
            return String(tool[range.upperBound...])
        }
        return tool
    }

    /// The brief (its first lines), a message from Claude, or the
    /// subagent's own words, a line each.
    private static func words(_ text: String, brief: Bool, from: String? = "↳ From Claude: ") -> [(String, FeedLine.Style)] {
        let lines = text.components(separatedBy: .newlines).map(printable).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return [] }
        if brief { return lines.prefix(3).map { ($0, .brief) } }
        guard let from else { return lines.map { ($0, .words) } }
        return [(from + lines[0], .words)] + lines.dropFirst().map { ($0, .words) }
    }

    private static func numbered(_ lines: some Collection<(String, FeedLine.Style)>) -> [FeedLine] {
        lines.enumerated().map { FeedLine(id: $0.offset, text: $0.element.0, style: $0.element.1) }
    }

    /// The task Claude gave a subagent, from the `agent-<id>.meta.json`
    /// Claude Code writes beside its transcript.
    private static func caption(_ transcript: String) -> String? {
        let meta = String(transcript.dropLast(".jsonl".count)) + ".meta.json"
        guard let data = FileManager.default.contents(atPath: meta),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let description = object["description"] as? String, !description.isEmpty else { return nil }
        return description
    }

    private static func resultText(_ content: Any?) -> String? {
        if let text = content as? String { return text }
        return (content as? [[String: Any]])?.lazy.compactMap { $0["text"] as? String }.first
    }

    private static func firstLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix { $0 != "\n" && $0 != "\r" })
    }

    private static let escapes = try? NSRegularExpression(
        pattern: "\u{1B}(\\[[0-?]*[ -/]*[@-~]|\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)?|[@-Z\\\\-_])")

    /// `text` without escape sequences or control characters but tabs.
    private static func printable(_ text: String) -> String {
        var text = text
        if let escapes {
            text = escapes.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { $0 == "\t" || !($0.value < 0x20 || $0.value == 0x7F) }))
    }

    /// The whole lines in the last `tail` bytes of a regular file.
    private static func tailData(_ path: String) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let start = max(0, size - tail)
        guard (try? handle.seek(toOffset: UInt64(start))) != nil, var data = try? handle.readToEnd() else { return nil }
        if start > 0, let newline = data.firstIndex(of: UInt8(ascii: "\n")) { data = data[(newline + 1)...] }
        return Data(data)
    }
}

/// The feeds of the tasks a view shows, read again each second while it
/// shows them; a file that hasn't changed isn't read again.
@MainActor
final class TaskFeedModel: ObservableObject {
    @Published private(set) var entries: [String: TaskFeedEntry] = [:]
    private var stamps: [String: Date] = [:]

    func watch(_ tasks: [PaneTask], limit: Int) async {
        while !Task.isCancelled {
            let known = stamps
            let read = await Task.detached(priority: .utility) {
                tasks.compactMap { task -> (String, Date, TaskFeedEntry)? in
                    guard let stamp = TaskFeed.stamp(task), stamp != known[task.id],
                          let entry = TaskFeed.read(task, limit: limit) else { return nil }
                    return (task.id, stamp, entry)
                }
            }.value
            for (id, stamp, entry) in read {
                stamps[id] = stamp
                if entries[id] != entry { entries[id] = entry }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
#endif
