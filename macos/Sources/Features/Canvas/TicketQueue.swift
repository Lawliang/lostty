#if os(macOS)
import Foundation

/// A `lostty +ticket` report from a pane, parsed from its LOSTTY_TICKET
/// user var: a JSON array of the command's arguments, such as
/// `["review", "TB-7", "Added the button"]`. Nothing past `init?(json:)`
/// sees the wire format.
enum TicketReport: Equatable {
    case review(key: String, note: String)
    case blocked(key: String, reason: String)

    static let userVar = "LOSTTY_TICKET"

    /// nil for anything but a known verb with its arguments and a key.
    init?(json: String) {
        guard let arguments = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else { return nil }
        let words = arguments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard words.count == 3, !words[1].isEmpty else { return nil }
        let key = words[1].uppercased()
        switch words[0] {
        case "review": self = .review(key: key, note: words[2])
        case "blocked": self = .blocked(key: key, reason: words[2])
        default: return nil
        }
    }

    var key: String {
        switch self {
        case .review(let key, _), .blocked(let key, _): key
        }
    }
}

/// The board's queue rules. Pure: each takes the canvas's tickets and
/// returns them changed, for `CanvasController.setTickets`. A feature
/// (a domain zone) has no order field: its queue is its queued tickets in
/// the order they sit in the tickets, and only these functions move one.
enum TicketQueue {
    /// What Lostty types into feature `domain`'s agent next: its first
    /// queued ticket that may start, and none while one there is working.
    /// With `autoStart` off, only one the owner started may.
    static func next(
        in domain: UUID, of tickets: [CanvasTicket], autoStart: Bool, startedByHand: Set<String>
    ) -> CanvasTicket? {
        let mine = tickets.filter { $0.zone == domain }
        guard !mine.contains(where: { $0.state == .working }) else { return nil }
        return mine.first { ticket in
            ticket.state == .queued && (autoStart || ticket.key.map(startedByHand.contains) == true)
        }
    }

    /// Ticket `key` typed into `pane`: working there. nil unless it was
    /// queued.
    static func delivering(_ key: String, into pane: UUID, in tickets: [CanvasTicket]) -> [CanvasTicket]? {
        changing(key, in: tickets) { $0.move(to: .working, by: .lostty(agent: pane)) }
    }

    /// Send back on a ticket in review or blocked: queued with the owner's
    /// `note`, in front of its feature's first queued ticket.
    static func sendingBack(_ key: String, note: String, in tickets: [CanvasTicket]) -> [CanvasTicket]? {
        guard let index = tickets.firstIndex(where: { $0.key == key }) else { return nil }
        var ticket = tickets[index]
        guard [.review, .blocked].contains(ticket.state), ticket.move(to: .queued, note: note, by: .owner) else {
            return nil
        }
        var result = tickets
        result.remove(at: index)
        let front = result.firstIndex { $0.zone == ticket.zone && $0.state == .queued } ?? index
        result.insert(ticket, at: front)
        return result
    }

    /// Ticket `key` into `zone` (a feature, or a project or none to wait
    /// for one): queued, at the back of that queue.
    static func assigning(_ key: String, to zone: UUID?, in tickets: [CanvasTicket]) -> [CanvasTicket]? {
        guard let index = tickets.firstIndex(where: { $0.key == key }) else { return nil }
        var ticket = tickets[index]
        ticket.zone = zone
        ticket.move(to: .queued, by: .owner)
        guard ticket != tickets[index] else { return nil }
        var result = tickets
        result.remove(at: index)
        result.append(ticket)
        return result
    }

    /// `ticket` in place of the one with its key. Newly done, it goes last,
    /// so the done show latest first.
    static func updating(_ ticket: CanvasTicket, in tickets: [CanvasTicket]) -> [CanvasTicket] {
        guard let index = tickets.firstIndex(where: { $0.key != nil && $0.key == ticket.key }) else { return tickets }
        var result = tickets
        if ticket.state == .done, tickets[index].state != .done {
            result.remove(at: index)
            result.append(ticket)
        } else {
            result[index] = ticket
        }
        return result
    }

    /// The tickets after `report` from a pane acting as `actor`; nil when
    /// the lifecycle refuses it, as for a pane outside the ticket's
    /// feature, or when it changes nothing, as a repeated report doesn't.
    static func applying(_ report: TicketReport, from actor: TicketActor, to tickets: [CanvasTicket]) -> [CanvasTicket]? {
        changing(report.key, in: tickets) { ticket in
            switch report {
            case .review(_, let note): ticket.move(to: .review, note: note.isEmpty ? nil : note, by: actor)
            case .blocked(_, let reason): ticket.move(to: .blocked, note: reason.isEmpty ? nil : reason, by: actor)
            }
        }
    }

    private static func changing(
        _ key: String, in tickets: [CanvasTicket], _ change: (inout CanvasTicket) -> Bool
    ) -> [CanvasTicket]? {
        guard let index = tickets.firstIndex(where: { $0.key == key }) else { return nil }
        var result = tickets
        return change(&result[index]) ? result : nil
    }
}
#endif
