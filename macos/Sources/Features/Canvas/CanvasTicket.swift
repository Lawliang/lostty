#if os(macOS)
import Foundation

/// A Jira-style ticket kept on the canvas: no Jira account, saved with the
/// canvas. It has a key (LT-1, or its project's prefix, as TB-1) once it's
/// created, and keeps it; until then it's a draft. It reads forgivingly: a field missing, or a type, priority or
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

    /// The key prefix of a ticket in no zone, as a Jira project's.
    static let defaultPrefix = "LT"
    /// Where the highest LT number handed out is kept. Each other prefix's
    /// number is kept under it with the prefix after a dot.
    static let lastNumberKey = "LosttyCanvasLastTicketNumber"

    /// Nil until the ticket is created.
    var key: String?
    var summary = ""
    var kind = Kind.task
    var priority = Priority.medium
    var status = Status.toDo
    var assignee = ""
    var details = ""
    /// The zone it was made in, a project or a domain; nil for none.
    var zone: UUID?

    var isCreated: Bool { key != nil }

    /// Something's been typed: throwing it away asks first.
    var hasTyping: Bool {
        [summary, assignee, details].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A ticket needs a summary, as Jira's do.
    var canSave: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// This ticket with whatever differs between `new` and `old` as it is
    /// in `old`: Undo of a change, leaving what changed since.
    func reverting(_ new: CanvasTicket, to old: CanvasTicket) -> CanvasTicket {
        var ticket = self
        if new.summary != old.summary { ticket.summary = old.summary }
        if new.kind != old.kind { ticket.kind = old.kind }
        if new.priority != old.priority { ticket.priority = old.priority }
        if new.status != old.status { ticket.status = old.status }
        if new.assignee != old.assignee { ticket.assignee = old.assignee }
        if new.details != old.details { ticket.details = old.details }
        return ticket
    }

    /// This ticket in no zone if its zone is one of `zones`, as when they're
    /// removed.
    func leaving(_ zones: Set<UUID>) -> CanvasTicket {
        var ticket = self
        if let zone, zones.contains(zone) { ticket.zone = nil }
        return ticket
    }

    /// The number in `key` (3 for LT-3); nil for a key with another prefix.
    static func number(of key: String, prefix: String = defaultPrefix) -> Int? {
        guard key.hasPrefix(prefix + "-") else { return nil }
        return Int(key.dropFirst(prefix.count + 1))
    }

    /// The key a new ticket with `prefix` gets: one past the highest number
    /// with it, used by a ticket on the canvas or by one since closed
    /// (`lastNumber`), so a number is never handed out twice.
    static func nextKey(prefix: String = defaultPrefix, after keys: [String], lastNumber: Int = 0) -> String {
        let highest = keys.compactMap { number(of: $0, prefix: prefix) }.max() ?? 0
        return "\(prefix)-\(max(highest, lastNumber) + 1)"
    }

    /// The key the next ticket with `prefix` will get, counting the numbers
    /// handed out app-wide (kept in `defaults`, so a deleted ticket's isn't
    /// handed out again, even once the canvas is emptied and so not saved).
    /// `take` hands it out.
    static func nextKey(
        prefix: String, after keys: [String], defaults: UserDefaults, take: Bool = false
    ) -> String {
        let stored = prefix == defaultPrefix ? lastNumberKey : "\(lastNumberKey).\(prefix)"
        let key = nextKey(prefix: prefix, after: keys, lastNumber: defaults.integer(forKey: stored))
        if take, let number = number(of: key, prefix: prefix) { defaults.set(number, forKey: stored) }
        return key
    }

    init(
        key: String? = nil, summary: String = "", kind: Kind = .task, priority: Priority = .medium,
        status: Status = .toDo, assignee: String = "", details: String = "", zone: UUID? = nil
    ) {
        self.key = key
        self.summary = summary
        self.kind = kind
        self.priority = priority
        self.status = status
        self.assignee = assignee
        self.details = details
        self.zone = zone
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
        zone = try? c.decodeIfPresent(UUID.self, forKey: .zone)
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

    /// The tickets panel's section of tickets with this status.
    var sectionTitle: String {
        switch self {
        case .toDo: "Up Next"
        case .inProgress: "In Progress"
        case .done: "Completed"
        }
    }

    /// The status after this one: Done goes back to To Do.
    var next: Self {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
#endif
