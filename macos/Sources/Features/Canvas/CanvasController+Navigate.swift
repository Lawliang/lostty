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
    /// its card at 100% and the pane focused. A beep with none.
    func jump() {
        let panes = Set(cards.flatMap { $0.surfaceTree.map(\.id) })
        guard let id = waits.next(after: focusedCard?.focusedSurface?.id, among: panes),
              let card = cards.first(where: { $0.surfaceTree.contains { $0.id == id } }),
              let surface = card.surfaceTree.first(where: { $0.id == id })
        else {
            NSSound.beep()
            return
        }
        if window?.isVisible != true { showWindow(nil) }
        zoom(to: card)
        card.focusSurface(surface)
    }

    /// ⌃⌥⌘ + arrows: focus the nearest card that way, panning to show it.
    func moveFocus(_ direction: CanvasModel.Direction) {
        guard let from = focusedCard, let id = model.neighbor(of: from.id, direction),
              let card = cards.first(where: { $0.id == id })
        else {
            NSSound.beep()
            return
        }
        reveal(card)
        focus(card)
    }
}
#endif
