#if os(macOS)
import Foundation

/// A Jira-style ticket kept on the canvas: no Jira account, saved with the
/// canvas. It has a key (LT-1, or its project's prefix, as TB-1) once it's
/// created, and keeps it; until then it's a draft. It reads forgivingly: a
/// field missing, or a type, priority or state this build doesn't know
/// (saved by a newer one), takes its default, so the canvas always comes
/// back.
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

    /// Where a ticket is on the zone board (board spec §2).
    enum State: String, Codable, CaseIterable, ForgivingCase {
        case queued, working, review, done, blocked
        static let fallback = State.queued

        /// The ticket lifecycle: whether `actor` may move a ticket in this
        /// state to `next`. A same-state move is refused, so a repeated
        /// report changes nothing.
        func allows(_ next: State, by actor: TicketActor) -> Bool {
            guard next != self else { return false }
            switch actor {
            case .lostty: return self == .queued && next == .working
            case .agent: return self == .working && (next == .review || next == .blocked)
            case .owner: return next != .working
            case .manager: return false
            }
        }
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
    /// Changed only by `move(to:note:by:)`, which keeps the lifecycle.
    private(set) var state = State.queued
    var assignee = ""
    var details = ""
    /// The zone it was made in, a project or a domain; nil for none. A
    /// domain is the ticket's feature.
    var zone: UUID?
    /// The last review or blocked line, or the owner's Send back note.
    private(set) var note: String?
    /// The pane Lostty last typed it into: the agent working on it.
    private(set) var agentPane: UUID?

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
        if new.state != old.state { ticket.state = old.state }
        if new.note != old.note { ticket.note = old.note }
        if new.zone != old.zone { ticket.zone = old.zone }
        if new.assignee != old.assignee { ticket.assignee = old.assignee }
        if new.details != old.details { ticket.details = old.details }
        return ticket
    }

    /// Moves it to `next` with `note` when `actor` may (`State.allows`);
    /// an agent moves only a ticket of its own domain. Lostty's move names
    /// the pane it typed into. False, and nothing changes, when refused.
    @discardableResult
    mutating func move(to next: State, note: String? = nil, by actor: TicketActor) -> Bool {
        guard state.allows(next, by: actor) else { return false }
        if case .agent(let domain) = actor, zone != domain { return false }
        state = next
        self.note = note
        if case .lostty(let pane) = actor { agentPane = pane }
        return true
    }

    /// Into `zone`, queued: a note on its work in the zone it left goes
    /// with it, as a move to queued drops one.
    mutating func assign(to zone: UUID?) {
        if zone != self.zone { note = nil }
        self.zone = zone
        move(to: .queued, by: .owner)
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
        assignee: String = "", details: String = "", zone: UUID? = nil, note: String? = nil
    ) {
        self.key = key
        self.summary = summary
        self.kind = kind
        self.priority = priority
        self.assignee = assignee
        self.details = details
        self.zone = zone
        self.note = note
    }

    /// `status` is what builds before the board saved, and still write
    /// so an older build keeps a finished ticket finished.
    private enum CodingKeys: String, CodingKey {
        case key, summary, kind, priority, state, status, assignee, details, zone, note, agentPane
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let blank = CanvasTicket()
        key = try c.decodeIfPresent(String.self, forKey: .key)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? blank.summary
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? blank.kind
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? blank.priority
        if let state = try c.decodeIfPresent(State.self, forKey: .state) {
            self.state = state
        } else {
            switch try? c.decodeIfPresent(String.self, forKey: .status) {
            case "inProgress": state = .working
            case "done": state = .done
            default: state = .queued
            }
        }
        assignee = try c.decodeIfPresent(String.self, forKey: .assignee) ?? blank.assignee
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? blank.details
        zone = try? c.decodeIfPresent(UUID.self, forKey: .zone)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        agentPane = try? c.decodeIfPresent(UUID.self, forKey: .agentPane)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encode(summary, forKey: .summary)
        try c.encode(kind, forKey: .kind)
        try c.encode(priority, forKey: .priority)
        try c.encode(state, forKey: .state)
        let status = switch state {
        case .done: "done"
        case .working: "inProgress"
        case .queued, .review, .blocked: "toDo"
        }
        try c.encode(status, forKey: .status)
        try c.encode(assignee, forKey: .assignee)
        try c.encode(details, forKey: .details)
        try c.encodeIfPresent(zone, forKey: .zone)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(agentPane, forKey: .agentPane)
    }
}

/// Who asks for a ticket to move (`CanvasTicket.State.allows`).
enum TicketActor: Equatable {
    /// The board's buttons and keys.
    case owner
    /// Lostty typing the ticket into pane `agent`.
    case lostty(agent: UUID)
    /// A pane in feature `domain`, by a `lostty +ticket` report.
    case agent(domain: UUID)
    /// Project `project`'s manager pane: it adds and assigns, and moves no
    /// state.
    case manager(project: UUID)
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

extension CanvasTicket.State {
    var title: String {
        switch self {
        case .queued: "Queued"
        case .working: "Working"
        case .review: "Review"
        case .done: "Done"
        case .blocked: "Blocked"
        }
    }

    /// Where it sits in its feature's section, top first.
    var rank: Int {
        switch self {
        case .working: 0
        case .queued: 1
        case .review: 2
        case .blocked: 3
        case .done: 4
        }
    }

    /// The states the owner can move a ticket to, for the keys and menus.
    static let byOwner = allCases.filter { next in allCases.contains { $0.allows(next, by: .owner) } }

    /// The state S moves to: the next of `byOwner`, round again.
    var next: Self {
        let all = Self.byOwner
        return all[((all.firstIndex(of: self) ?? -1) + 1) % all.count]
    }
}
#endif
