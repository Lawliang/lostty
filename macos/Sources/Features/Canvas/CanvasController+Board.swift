#if os(macOS)
import AppKit

/// The zone board's side of the canvas: Start and Send back from the
/// tickets panels. What decides is TicketQueue's; this writes through
/// `setTickets`.
extension CanvasController {
    /// Start on a queued ticket: it goes in when its feature's agent is
    /// free, auto-start or not. Not undoable: it types into a terminal.
    func start(_ key: String) {
        guard startedByHand.insert(key).inserted else { return }
        relistTickets()
    }

    /// Send back on a ticket in review or blocked: queued at the front of
    /// its feature's queue with the owner's `note`, and started. Not
    /// undoable: it types into a terminal.
    func sendBack(_ key: String, note: String) {
        guard let sent = TicketQueue.sendingBack(key, note: note, in: tickets) else { return }
        startedByHand.insert(key)
        setTickets(sent)
    }

    /// Whether `ticket`'s project starts its tickets without Start.
    func autoStarts(_ ticket: CanvasTicket) -> Bool {
        ticket.zone.flatMap(model.projectZone).flatMap { model.zone($0)?.autoStart } ?? false
    }

    /// The title of the card holding pane `pane`, as its header shows it.
    func agentTitle(_ pane: UUID) -> String? {
        cards.first { $0.surfaceTree.contains { $0.id == pane } }?.title
    }
}
#endif
