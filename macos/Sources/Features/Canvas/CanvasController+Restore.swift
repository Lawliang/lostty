#if os(macOS)
import AppKit

extension CanvasController {
    /// What the app saves for the canvas: shown or not, the view, the
    /// cards back to front, the tickets with their panel, and the zones.
    func restorableState() -> CanvasRestorableState {
        let visible = scrollView.documentVisibleRect
        // Never shown since launch: the view it came back with.
        let view = placed ? (CGPoint(x: visible.midX, y: visible.midY), scrollView.magnification)
            : (pendingView ?? (CanvasModel.middle, 1))
        let saved = model.cards.compactMap { entry -> CanvasSaved<SplitTree<Ghostty.SurfaceView>>.Card? in
            guard let card = cards.first(where: { $0.id == entry.id }), !card.surfaceTree.isEmpty else { return nil }
            return .init(frame: entry.frame, tree: card.surfaceTree, focused: card.focusedSurface?.id.uuidString)
        }
        let stack = model.cards.firstIndex { $0.id == tickets.id }
        let board = CanvasSaved<SplitTree<Ghostty.SurfaceView>>.Board(
            tickets: tickets.list.tickets, frame: stack.map { model.cards[$0].frame }, stack: stack, draft: tickets.draft)
        return CanvasRestorableState(saved: .init(
            visible: window?.isVisible ?? false, center: view.0, zoom: view.1, cards: saved, board: board, zones: model.zones))
    }

    /// Rebuilds the canvas at launch; shown only if it was.
    static func restore(_ ghostty: Ghostty.App, state: CanvasRestorableState) {
        guard !state.saved.isEmpty else { return }
        let canvas = shared ?? CanvasController(ghostty)
        shared = canvas
        // Zones first: a pane restored into its zone hasn't moved there.
        canvas.addZones(state.saved.zones)
        for card in state.saved.cards {
            let focused = card.focused.flatMap { id in card.tree.first { $0.id.uuidString == id } }
            canvas.addCard(tree: card.tree, frame: card.frame, focused: focused)
        }
        canvas.restoreTickets(state.saved)
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

    /// The tickets back in the panel, and the panel back where it stood
    /// among the cards if it was open. Tickets saved as cards (before the
    /// panel) join it, and it opens where the front one was. A ticket
    /// already in the panel (reopened from history) isn't added twice.
    private func restoreTickets<Tree>(_ saved: CanvasSaved<Tree>) {
        let old = (saved.tickets ?? []).sorted { $0.stack < $1.stack }
        tickets.list.merge((saved.board?.tickets ?? []) + old.map(\.ticket))
        if tickets.draft == nil { tickets.draft = saved.board?.draft }
        if let frame = saved.board?.frame {
            openTickets(frame: frame, stack: saved.board?.stack)
        } else if let front = old.last(where: \.ticket.isCreated) {
            openTickets(
                frame: CGRect(origin: front.frame.origin, size: TicketBoardView.newSize), stack: front.stack)
        }
    }
}
#endif
