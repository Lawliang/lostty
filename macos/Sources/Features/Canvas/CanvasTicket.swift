#if os(macOS)
import Foundation

/// A Jira-style ticket kept on the canvas: no Jira account, saved with the
/// canvas. It has a key (LT-1, LT-2…) once it's created; until then it's a
/// draft. It reads forgivingly: a field missing, or a type, priority or
/// status this build doesn't know (saved by a newer one), takes its
/// default, so the canvas always comes back.
struct CanvasTicket: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, ForgivingCase {
        case task, bug, story
        static let fallback = Kind.task
    }

    /// Jira's five, highest first.
    enum Priority: String, Codable, CaseIterable, ForgivingCase {
        case highest, high, medium, low, lowest
        static let fallback = Priority.medium
    }

    enum Status: String, Codable, CaseIterable, ForgivingCase {
        case toDo, inProgress, done
        static let fallback = Status.toDo
    }

    /// Every ticket's key starts with this, as a Jira project's do.
    static let prefix = "LT"

    /// Nil until the ticket is created.
    var key: String?
    var summary = ""
    var kind = Kind.task
    var priority = Priority.medium
    var status = Status.toDo
    var assignee = ""
    var details = ""

    var isCreated: Bool { key != nil }

    /// Something's been typed: throwing it away asks first.
    var hasTyping: Bool {
        [summary, assignee, details].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A ticket needs a summary, as Jira's do.
    var canSave: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The number in `key` (3 for LT-3); nil for any other key.
    static func number(of key: String) -> Int? {
        guard key.hasPrefix(prefix + "-") else { return nil }
        return Int(key.dropFirst(prefix.count + 1))
    }

    /// The key a new ticket gets: one past the highest number used, by a
    /// ticket on the canvas or by one since closed (`lastNumber`), so a
    /// number is never handed out twice.
    static func nextKey(after keys: [String], lastNumber: Int = 0) -> String {
        let highest = keys.compactMap(number(of:)).max() ?? 0
        return "\(prefix)-\(max(highest, lastNumber) + 1)"
    }

    init(
        key: String? = nil, summary: String = "", kind: Kind = .task, priority: Priority = .medium,
        status: Status = .toDo, assignee: String = "", details: String = ""
    ) {
        self.key = key
        self.summary = summary
        self.kind = kind
        self.priority = priority
        self.status = status
        self.assignee = assignee
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let blank = CanvasTicket()
        key = try c.decodeIfPresent(String.self, forKey: .key)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? blank.summary
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? blank.kind
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? blank.priority
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? blank.status
        assignee = try c.decodeIfPresent(String.self, forKey: .assignee) ?? blank.assignee
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? blank.details
    }
}

/// An enum that reads a case it doesn't know as `fallback`.
protocol ForgivingCase: RawRepresentable<String>, Decodable {
    static var fallback: Self { get }
}

extension ForgivingCase {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .fallback
    }
}

extension CanvasTicket.Kind {
    var title: String {
        switch self {
        case .task: "Task"
        case .bug: "Bug"
        case .story: "Story"
        }
    }
}

extension CanvasTicket.Priority {
    var title: String {
        switch self {
        case .highest: "Highest"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        case .lowest: "Lowest"
        }
    }
}

extension CanvasTicket.Status {
    var title: String {
        switch self {
        case .toDo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}
#endif
