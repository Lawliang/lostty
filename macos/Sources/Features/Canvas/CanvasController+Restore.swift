#if os(macOS)
import AppKit

extension CanvasController {
    /// What the app saves for the canvas: shown or not, the view, the
    /// cards back to front, and the tickets.
    func restorableState() -> CanvasRestorableState {
        let visible = scrollView.documentVisibleRect
        // Never shown since launch: the view it came back with.
        let view = placed ? (CGPoint(x: visible.midX, y: visible.midY), scrollView.magnification)
            : (pendingView ?? (CanvasModel.middle, 1))
        let saved = model.cards.compactMap { entry -> CanvasSaved<SplitTree<Ghostty.SurfaceView>>.Card? in
            guard let card = cards.first(where: { $0.id == entry.id }), !card.surfaceTree.isEmpty else { return nil }
            return .init(frame: entry.frame, tree: card.surfaceTree, focused: card.focusedSurface?.id.uuidString)
        }
        // Created tickets only: a draft is thrown away.
        let tickets = model.cards.enumerated().compactMap { stack, entry -> CanvasSaved<SplitTree<Ghostty.SurfaceView>>.Ticket? in
            guard let ticket = self.tickets[entry.id]?.ticket.ticket, ticket.isCreated else { return nil }
            return .init(id: entry.id, frame: entry.frame, ticket: ticket, stack: stack)
        }
        return CanvasRestorableState(saved: .init(
            visible: window?.isVisible ?? false, center: view.0, zoom: view.1, cards: saved,
            tickets: tickets, lastTicketNumber: lastTicketNumber))
    }

    /// Rebuilds the canvas at launch; shown only if it was.
    static func restore(_ ghostty: Ghostty.App, state: CanvasRestorableState) {
        guard !state.saved.isEmpty else { return }
        let canvas = shared ?? CanvasController(ghostty)
        shared = canvas
        for card in state.saved.cards {
            let focused = card.focused.flatMap { id in card.tree.first { $0.id.uuidString == id } }
            canvas.addCard(tree: card.tree, frame: card.frame, focused: focused)
        }
        // Back where they stood among the cards; a ticket already on the
        // canvas (reopened from history) isn't brought back twice.
        let tickets = (state.saved.tickets ?? []).filter { canvas.tickets[$0.id] == nil }
        for ticket in tickets.sorted(by: { $0.stack < $1.stack }) {
            canvas.addTicket(ticket.ticket, id: ticket.id, frame: ticket.frame, stack: ticket.stack)
        }
        canvas.lastTicketNumber = max(canvas.lastTicketNumber, state.saved.lastTicketNumber ?? 0)
        canvas.pendingView = (state.saved.center, state.saved.zoom)
        // The front card was the focused one: it takes keyboard focus when
        // the canvas is next key, not now (that would pull it forward).
        if let front = canvas.frontCard {
            canvas.cardWillFocus(front)
            canvas.cardDidFocus(front)
        }
        if state.saved.visible {
            canvas.showWindow(nil)
        } else {
            // Hidden: its panes run but don't draw until it's opened.
            canvas.updateVisibility()
        }
    }
}
#endif
