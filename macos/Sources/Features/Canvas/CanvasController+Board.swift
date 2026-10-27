#if os(macOS)
import AppKit

/// The zone board's side of the canvas: Start and Send back from the
/// tickets panels, and typing each feature's next ticket into its agent.
/// What decides is TicketQueue's and TicketDelivery's; this reads the
/// panes and writes through `setTickets`.
extension CanvasController {
    /// How often Lostty looks again while a ticket may start and no pane
    /// can take it: a Claude just started, or input typed and cleared,
    /// sends no signal.
    static let deliveryRetry: TimeInterval = 2

    /// Start on a queued ticket: it goes in when its feature's agent is
    /// free, auto-start or not. Not undoable: it types into a terminal.
    func start(_ key: String) {
        guard startedByHand.insert(key).inserted else { return }
        relistTickets()
        deliverSoon()
    }

    /// Send back on a ticket in review or blocked: queued at the front of
    /// its feature's queue with the owner's `note`, and started. Not
    /// undoable: it types into a terminal.
    func sendBack(_ key: String, note: String) {
        guard let sent = TicketQueue.sendingBack(key, note: note, in: tickets) else { return }
        startedByHand.insert(key)
        setTickets(sent)
    }

    /// A user var from pane `pane`: a `lostty +ticket` report, parsed here,
    /// at the boundary. Anything else, or a report that doesn't parse, is
    /// ignored.
    static func userVarChanged(_ pane: UUID, name: String, value: String) {
        guard name == TicketReport.userVar, let report = TicketReport(json: value) else { return }
        shared?.ticketReported(report, from: pane)
    }

    /// Applied when the pane's role may make it (`TicketQueue.applying`);
    /// else dropped without a word, since the CLI can't hear back.
    func ticketReported(_ report: TicketReport, from pane: UUID) {
        guard let actor = model.ticketRole(of: pane, panes: membership.panes),
              let reported = TicketQueue.applying(
                report, from: actor, to: tickets, in: model, newKey: { nextTicketKey(in: $0, take: true) }) else { return }
        setTickets(reported)
    }

    /// Whether `ticket`'s project starts its tickets without Start.
    func autoStarts(_ ticket: CanvasTicket) -> Bool {
        ticket.zone.flatMap(model.projectZone).flatMap { model.zone($0)?.autoStart } ?? false
    }

    /// Each terminal card's title bar shows the key of the ticket working
    /// in one of its panes.
    func showTicketKeys() {
        let working = TicketQueue.working(tickets)
        for card in cards {
            let key = card.surfaceTree.lazy.compactMap { working[$0.id] }.first
            if card.ticketKey != key { card.ticketKey = key }
        }
    }

    /// The title of the card holding pane `pane`, as its header shows it.
    func agentTitle(_ pane: UUID) -> String? {
        cards.first { $0.surfaceTree.contains { $0.id == pane } }?.title
    }

    /// One delivery attempt `delay` from now, never inside the caller's
    /// turn: a delivery's own `setTickets` asks for the next. A later call
    /// replaces one still waiting.
    func deliverSoon(after delay: TimeInterval = 0) {
        deliveryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.deliverReadyTickets() } }
        deliveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// For each feature, the ticket that may start (TicketQueue.next) goes
    /// to the first of its panes, in card order and not the project's
    /// manager, whose Claude is off and whose screen shows an empty input
    /// box. It's typed first and marked working only once typing took, in
    /// this one turn; with nothing typed it stays queued and Lostty looks
    /// again.
    func deliverReadyTickets() {
        deliveryWork = nil
        startedByHand = startedByHand.filter { key in tickets.contains { $0.key == key && $0.state == .queued } }
        let panes = cards.flatMap { Array($0.surfaceTree) }
        var next = tickets
        var waiting = false
        for domain in model.zones {
            guard let parent = domain.parent, let project = model.zone(parent),
                  let ticket = TicketQueue.next(
                    in: domain.id, of: next, autoStart: project.autoStart == true, startedByHand: startedByHand),
                  let key = ticket.key else { continue }
            let agent = panes.first { pane in
                membership.panes.zones[pane.id] == domain.id && pane.id != project.manager
                    && ClaudeRuntime.shared.phase(pane.id).isOff
                    && TicketDelivery.input(in: TicketDelivery.screen(of: pane)) == .empty
            }
            guard let agent, let delivered = TicketQueue.delivering(key, into: agent.id, in: next),
                  TicketDelivery.type(TicketDelivery.prompt(for: ticket, feature: domain.name), into: agent) else {
                waiting = true
                continue
            }
            next = delivered
            startedByHand.remove(key)
        }
        setTickets(next)
        if waiting, deliveryWork == nil { deliverSoon(after: Self.deliveryRetry) }
    }
}
#endif
