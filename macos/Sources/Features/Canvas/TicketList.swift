#if os(macOS)
import Foundation

/// A section of a tickets panel (board spec §3).
enum TicketSection: Hashable {
    /// A domain zone's tickets: one feature's.
    case feature(UUID)
    /// Tickets in a project or in no zone, waiting for a feature.
    case toAssign
}

/// A tickets panel's list: the tickets of the zones it shows, in sections
/// by feature, the one selected, and the sections folded away. Pure; each
/// panel's TicketBoard makes one from the canvas's tickets and its own
/// zones, sections, selection and folds.
struct TicketList: Equatable {
    /// Every ticket, each created (it has a key), in queue order
    /// (`TicketQueue`).
    private(set) var tickets: [CanvasTicket] = []
    /// The selected ticket's key.
    var selected: String?
    var folded: Set<TicketSection> = []
    /// The zones whose tickets show; nil for every ticket.
    private(set) var zones: Set<UUID>?
    /// Top to bottom (`CanvasModel.ticketSections`).
    private(set) var sections: [TicketSection] = [.toAssign]

    init(tickets: [CanvasTicket] = []) {
        merge(tickets)
    }

    /// `tickets` as they are, created and in order, showing those of
    /// `zones`. A selected ticket that doesn't show isn't selected.
    init(
        tickets: [CanvasTicket], zones: Set<UUID>?, sections: [TicketSection], selected: String?,
        folded: Set<TicketSection>
    ) {
        self.tickets = tickets
        self.zones = zones
        self.sections = sections
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

    /// Its feature's section, else To assign.
    func section(of ticket: CanvasTicket) -> TicketSection {
        let feature = ticket.zone.map(TicketSection.feature)
        return feature.flatMap { sections.contains($0) ? $0 : nil } ?? .toAssign
    }

    /// A section's tickets top to bottom: the agent's current ticket, the
    /// queue in the order Lostty types it, what waits on the owner, then
    /// what's done, latest first.
    func tickets(in section: TicketSection) -> [CanvasTicket] {
        let these = tickets.filter { shows($0) && self.section(of: $0) == section }
        let rows = these.enumerated().sorted { a, b in
            let (rankA, rankB) = (a.element.state.rank, b.element.state.rank)
            guard rankA == rankB else { return rankA < rankB }
            return a.element.state == .done ? a.offset > b.offset : a.offset < b.offset
        }
        return rows.map(\.element)
    }

    /// The keys of the rows showing, top to bottom: the unfolded sections'.
    var shown: [String] {
        sections.filter { !folded.contains($0) }.flatMap { tickets(in: $0).compactMap(\.key) }
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
    mutating func fold(_ section: TicketSection, _ fold: Bool = true) {
        if fold {
            folded.insert(section)
        } else {
            folded.remove(section)
        }
        guard fold, let selected, let ticket = ticket(selected), self.section(of: ticket) == section else { return }
        let after = sections.drop { $0 != section }.dropFirst().filter { !folded.contains($0) }
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
        folded.remove(section(of: ticket))
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
    /// goes to the top of the done; moved to another feature, its section
    /// unfolds, so it doesn't vanish.
    mutating func update(_ ticket: CanvasTicket) {
        guard let key = ticket.key, let old = self.ticket(key) else { return }
        tickets = TicketQueue.updating(ticket, in: tickets)
        if section(of: old) != section(of: ticket) { folded.remove(section(of: ticket)) }
    }

    /// The Feature menu: ticket `key` into `zone`, at the back of its queue.
    mutating func assign(_ key: String, to zone: UUID?) {
        guard let assigned = TicketQueue.assigning(key, to: zone, in: tickets) else { return }
        tickets = assigned
        if let ticket = ticket(key) { folded.remove(section(of: ticket)) }
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
