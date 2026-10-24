#if os(macOS)
import Foundation

/// The tickets panel's list: every ticket, in sections by status, the one
/// selected, and the sections folded away. Pure; TicketBoard publishes it.
struct TicketList: Equatable {
    /// The sections top to bottom: what's under way, what's next, what's done.
    static let sections: [CanvasTicket.Status] = [.inProgress, .toDo, .done]

    /// Every ticket, each created (it has a key), oldest first, but for
    /// one moved to Done, which goes last: Completed shows the latest first.
    private(set) var tickets: [CanvasTicket] = []
    /// The selected ticket's key.
    var selected: String?
    var folded: Set<CanvasTicket.Status> = []

    init(tickets: [CanvasTicket] = []) {
        merge(tickets)
    }

    func ticket(_ key: String) -> CanvasTicket? {
        tickets.first { $0.key == key }
    }

    func count(_ status: CanvasTicket.Status) -> Int {
        tickets.filter { $0.status == status }.count
    }

    /// A section's tickets top to bottom: In Progress and Up Next highest
    /// priority first, then oldest first; Completed latest first.
    func tickets(in status: CanvasTicket.Status) -> [CanvasTicket] {
        let these = tickets.filter { $0.status == status }
        guard status != .done else { return these.reversed() }
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
    mutating func fold(_ status: CanvasTicket.Status, _ fold: Bool = true) {
        if fold {
            folded.insert(status)
        } else {
            folded.remove(status)
        }
        guard fold, let selected, ticket(selected)?.status == status else { return }
        let after = Self.sections.drop { $0 != status }.dropFirst().filter { !folded.contains($0) }
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
        folded.remove(ticket.status)
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
        guard let key = ticket.key, let index = tickets.firstIndex(where: { $0.key == key }) else { return }
        let moved = tickets[index].status != ticket.status
        if moved, ticket.status == .done {
            tickets.remove(at: index)
            tickets.append(ticket)
        } else {
            tickets[index] = ticket
        }
        if moved { folded.remove(ticket.status) }
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
