#if os(macOS)
import AppKit

extension CanvasController {
    /// The zoom changed (a pinch): once it holds still for a moment, the
    /// terminals re-render at it.
    func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settleZoom() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CanvasZoom.settle, execute: work)
    }

    /// ⌃⌘J: the next pane waiting on you, oldest first, round and round:
    /// its card at 100% and the pane focused. Nothing, when none is.
    func jump() {
        let panes = Set(cards.flatMap { $0.surfaceTree.map(\.id) })
        guard let id = waits.next(after: focusedCard?.focusedSurface?.id, among: panes),
              let card = cards.first(where: { $0.surfaceTree.contains { $0.id == id } }),
              let surface = card.surfaceTree.first(where: { $0.id == id })
        else { return }
        if window?.isVisible != true { showWindow(nil) }
        zoom(to: card)
        card.focusSurface(surface)
    }

    /// The cards whose terminals wait on you, oldest first, for the arrows
    /// at the canvas's edges; none unless Notifications is set to Arrows.
    func arrowTargets() -> [CanvasArrows.Target] {
        guard NotificationPreferences.shared.showsArrows else { return [] }
        return waits.order.compactMap { pane in
            guard let card = cards.first(where: { $0.surfaceTree.contains { $0.id == pane } }),
                  let frame = model.card(card.id)?.frame else { return nil }
            let title = headerTitle(ofPane: pane)
            return CanvasArrows.Target(pane: pane, frame: frame, name: title?.agent ?? title?.topic)
        }
    }

    /// Clicking an arrow: its card at 100%, the waiting pane focused.
    func goToWaiting(_ pane: UUID) {
        guard let card = cards.first(where: { $0.surfaceTree.contains { $0.id == pane } }),
              let surface = card.surfaceTree.first(where: { $0.id == pane }) else { return }
        zoom(to: card)
        card.focusSurface(surface)
    }

    /// ⌃⌥⌘ + arrows: focus the nearest terminal card that way, panning to
    /// show it.
    func moveFocus(_ direction: CanvasModel.Direction) {
        guard let from = focusedCard, let id = model.neighbor(of: from.id, direction, among: Set(cards.map(\.id))),
              let card = cards.first(where: { $0.id == id })
        else { return }
        reveal(card)
        focus(card)
    }
}
#endif
