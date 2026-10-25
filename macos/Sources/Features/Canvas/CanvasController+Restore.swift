#if os(macOS)
import AppKit

extension CanvasController {
    /// What the app saves for the canvas: shown or not, the view, the
    /// cards back to front, the tickets with their panels, and the zones.
    func restorableState() -> CanvasRestorableState {
        let visible = scrollView.documentVisibleRect
        // Never shown since launch: the view it came back with.
        let view = placed ? (CGPoint(x: visible.midX, y: visible.midY), scrollView.magnification)
            : (pendingView ?? (CanvasModel.middle, 1))
        let saved = model.cards.compactMap { entry -> CanvasSaved<SplitTree<Ghostty.SurfaceView>>.Card? in
            guard let card = cards.first(where: { $0.id == entry.id }), !card.surfaceTree.isEmpty else { return nil }
            return .init(frame: entry.frame, tree: card.surfaceTree, focused: card.focusedSurface?.id.uuidString)
        }
        let panels = model.cards.enumerated().compactMap { stack, entry in
            ticketPanels[entry.id].map { CanvasSaved<SplitTree<Ghostty.SurfaceView>>.Board.Panel(
                frame: entry.frame, stack: stack, draft: $0.board.draft) }
        }
        let board = CanvasSaved<SplitTree<Ghostty.SurfaceView>>.Board(tickets: tickets, panels: panels, draft: parkedDraft)
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
        // A Lostty running beside this one (a Debug build and the
        // installed app) shares the zone files' folder: its panes' aren't stale.
        let alone = !NSWorkspace.shared.runningApplications.contains { app in
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && ["com.lawliang.lostty", "com.lawliang.lostty.debug"].contains(app.bundleIdentifier ?? "")
        }
        if alone { canvas.zoneStore.sweep(keeping: Set(canvas.cards.flatMap { $0.surfaceTree.map(\.id) })) }
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

    /// The tickets back, and the panels back where they stood among the
    /// cards, unless one is open (the canvas reopened from history).
    /// Tickets saved as cards (before the panels) join them, and a panel
    /// opens where the front one was. A ticket already on the canvas isn't
    /// added twice.
    private func restoreTickets<Tree>(_ saved: CanvasSaved<Tree>) {
        let old = (saved.tickets ?? []).sorted { $0.stack < $1.stack }
        var list = TicketList(tickets: tickets)
        list.merge((saved.board?.tickets ?? []) + old.map(\.ticket))
        setTickets(list.tickets)
        if parkedDraft == nil { parkedDraft = saved.board?.draft }
        guard ticketPanels.isEmpty else { return }
        let panels = (saved.board?.panels ?? []).sorted { $0.stack < $1.stack }
        for panel in panels {
            openTickets(frame: panel.frame, stack: panel.stack, draft: panel.draft)
        }
        if panels.isEmpty, let front = old.last(where: \.ticket.isCreated) {
            openTickets(
                frame: CGRect(origin: front.frame.origin, size: TicketBoardView.newSize), stack: front.stack)
        }
    }
}
#endif
