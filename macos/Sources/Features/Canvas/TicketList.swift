#if os(macOS)
import Foundation

/// A tickets panel's list: the tickets of the zones it shows, in sections
/// by state, the one selected, and the sections folded away. Pure; each
/// panel's TicketBoard makes one from the canvas's tickets and its own
/// zones, selection and folds.
struct TicketList: Equatable {
    /// The sections top to bottom: what's under way, what's next, what's done.
    static let sections: [CanvasTicket.State] = [.working, .queued, .review, .blocked, .done]

    /// Every ticket, each created (it has a key), oldest first, but for
    /// one moved to Done, which goes last: Completed shows the latest first.
    private(set) var tickets: [CanvasTicket] = []
    /// The selected ticket's key.
    var selected: String?
    var folded: Set<CanvasTicket.State> = []
    /// The zones whose tickets show; nil for every ticket.
    private(set) var zones: Set<UUID>?

    init(tickets: [CanvasTicket] = []) {
        merge(tickets)
    }

    /// `tickets` as they are, created and in order, showing those of
    /// `zones`. A selected ticket that doesn't show isn't selected.
    init(tickets: [CanvasTicket], zones: Set<UUID>?, selected: String?, folded: Set<CanvasTicket.State>) {
        self.tickets = tickets
        self.zones = zones
        self.folded = folded
        self.selected = selected.flatMap { ticket($0) }.flatMap { shows($0) ? $0.key : nil }
    }

    func shows(_ ticket: CanvasTicket) -> Bool {
        guard let zones else { return true }
        return ticket.zone.map(zones.contains) ?? false
    }

    func ticket(_ key: String) -> CanvasTicket? {
        tickets.first { $0.key == key }
    }

    func count(_ state: CanvasTicket.State) -> Int {
        tickets.filter { $0.state == state && shows($0) }.count
    }

    /// A section's tickets top to bottom: Done latest first, the rest
    /// highest priority first, then oldest first.
    func tickets(in state: CanvasTicket.State) -> [CanvasTicket] {
        let these = tickets.filter { $0.state == state && shows($0) }
        guard state != .done else { return these.reversed() }
        let rank = { (ticket: CanvasTicket) in CanvasTicket.Priority.allCases.firstIndex(of: ticket.priority) ?? 0 }
        return these.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// The keys of the rows showing, top to bottom: the unfolded sections'.
    var shown: [String] {
        Self.sections.filter { !folded.contains($0) }.flatMap { tickets(in: $0).compactMap(\.key) }
    }

    /// The selection `delta` rows down (up when negative), stopping at the
    /// ends; with none showing, the first row or the last.
    mutating func move(by delta: Int) {
        let rows = shown
        guard !rows.isEmpty else { return }
        guard let selected, let index = rows.firstIndex(of: selected) else {
            self.selected = delta > 0 ? rows.first : rows.last
            return
        }
        self.selected = rows[min(max(index + delta, 0), rows.count - 1)]
    }

    /// The first row, or the last.
    mutating func moveToEnd(last: Bool) {
        selected = last ? shown.last : shown.first
    }

    /// Folds or unfolds a section. A selected ticket folded away hands the
    /// selection to the first row after its section, or else the last row.
    mutating func fold(_ state: CanvasTicket.State, _ fold: Bool = true) {
        if fold {
            folded.insert(state)
        } else {
            folded.remove(state)
        }
        guard fold, let selected, ticket(selected)?.state == state else { return }
        let after = Self.sections.drop { $0 != state }.dropFirst().filter { !folded.contains($0) }
        for section in after {
            if let key = tickets(in: section).first?.key {
                self.selected = key
                return
            }
        }
        self.selected = shown.last
    }

    /// Adds a created ticket, at `index` among them (last by default), and
    /// selects it, its section unfolded.
    mutating func add(_ ticket: CanvasTicket, at index: Int? = nil) {
        guard let key = ticket.key, self.ticket(key) == nil else { return }
        tickets.insert(ticket, at: min(index ?? tickets.count, tickets.count))
        folded.remove(ticket.state)
        selected = key
    }

    /// Takes a ticket out, the selection going to the row below it, or
    /// else above. Returns it and where it was, for Undo.
    @discardableResult
    mutating func remove(_ key: String) -> (ticket: CanvasTicket, index: Int)? {
        guard let index = tickets.firstIndex(where: { $0.key == key }) else { return nil }
        let rows = shown
        if selected == key, let row = rows.firstIndex(of: key) {
            selected = row + 1 < rows.count ? rows[row + 1] : row > 0 ? rows[row - 1] : nil
        }
        return (tickets.remove(at: index), index)
    }

    /// Puts `ticket` in place of the one with its key. Moved to Done, it
    /// goes to the top of Completed; moved anywhere, its section unfolds,
    /// so it doesn't vanish.
    mutating func update(_ ticket: CanvasTicket) {
        guard let key = ticket.key, let old = self.ticket(key) else { return }
        tickets = TicketQueue.updating(ticket, in: tickets)
        if old.state != ticket.state { folded.remove(ticket.state) }
    }

    /// Adds the created tickets it hasn't got a ticket with the same key
    /// for, as a restore does; with none selected, selects the first row.
    mutating func merge(_ more: [CanvasTicket]) {
        for ticket in more where ticket.isCreated && self.ticket(ticket.key ?? "") == nil {
            tickets.append(ticket)
        }
        if selected == nil { selected = shown.first }
    }
}
#endif
