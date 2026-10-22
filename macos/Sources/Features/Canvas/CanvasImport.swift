#if os(macOS)
import AppKit

/// Every terminal window onto the canvas at once: Window → Move All Windows
/// to Canvas, or asked when the canvas first opens, or one window moves to
/// it, while other windows are open. Each window (each tab) becomes a card,
/// splits and all; nothing restarts.
@MainActor
enum CanvasImport {
    /// The remembered answer, once "Don't ask again" is checked.
    static let key = "LosttyCanvasMoveAllWindows"

    /// The terminal windows, front to back, `first` first; a tab is a
    /// window of its own.
    static func windows(first: TerminalController? = nil) -> [TerminalController] {
        let front = NSApp.orderedWindows.compactMap { $0.windowController as? TerminalController }
        var all = front + TerminalController.all.filter { !front.contains($0) }
        if let first, let index = all.firstIndex(of: first) {
            all.insert(all.remove(at: index), at: 0)
        }
        return all.filter { !$0.surfaceTree.isEmpty }
    }

    /// Whether to move every window: the remembered answer, else asked.
    /// `moving` is how many windows the question is about; `opening`, that
    /// it's asked as the canvas opens rather than as one window moves.
    static func shouldMoveAll(_ moving: Int, opening: Bool, defaults: UserDefaults = .standard) -> Bool {
        if let remembered = remembered(in: defaults) { return remembered }
        let alert = NSAlert()
        if opening {
            alert.messageText = moving == 1 ? "Bring your window onto the canvas?" : "Bring your \(moving) windows onto the canvas?"
            alert.addButton(withTitle: moving == 1 ? "Move It" : "Move All \(moving)")
            alert.addButton(withTitle: "Start Empty")
        } else {
            alert.messageText = moving == 2 ? "Move your other window too?" : "Move your \(moving - 1) other windows too?"
            alert.addButton(withTitle: "Move All \(moving)")
            alert.addButton(withTitle: "Just This One")
        }
        alert.informativeText = "Each window becomes a card, splits and all. Nothing restarts. "
            + "Window → Move All Windows to Canvas does this any time."
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let all = alert.runModal() == .alertFirstButtonReturn
        if alert.suppressionButton?.state == .on { defaults.set(all, forKey: key) }
        return all
    }

    static func remembered(in defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    /// Moves `controllers`' panes onto the canvas, closing their windows,
    /// and focuses `focus`'s card (else the first); several are zoomed to
    /// fit. `arrived` gets the new cards once they're on the canvas.
    static func move(
        _ ghostty: Ghostty.App, _ controllers: [TerminalController], focus: TerminalController? = nil,
        arrived: @escaping ([CardController]) -> Void = { _ in }
    ) {
        let moves = controllers.filter { !$0.surfaceTree.isEmpty }.map {
            (tree: $0.surfaceTree, focused: $0.focusedSurface, size: CanvasController.cardSize(for: $0.surfaceTree),
             isFocus: $0 === (focus ?? controllers.first))
        }
        guard !moves.isEmpty, LosttyChannel.current.hasCanvas else { return }
        // The canvas first: with quit-after-last-window-closed, closing the
        // last window with no other open would quit and end the moved panes.
        let canvas = CanvasController.show(ghostty, freshCard: false)
        // An empty tree closes a window (surfaceTreeDidChange).
        for controller in controllers { controller.surfaceTree = .init() }
        // The cards take the panes once the windows' views have let them go.
        DispatchQueue.main.async {
            let frames = canvas.model.placements(sizes: moves.map(\.size), in: canvas.scrollView.documentVisibleRect)
            var focused: CardController?
            var cards: [CardController] = []
            for (move, frame) in zip(moves, frames) {
                let card = canvas.addCard(tree: move.tree, frame: frame, focused: move.focused)
                cards.append(card)
                if move.isFocus { focused = card }
            }
            // Focusing pans to the card; then the fit shows them all, at
            // no more than 100%.
            if let focused { canvas.focus(focused) }
            if moves.count > 1 { canvas.zoomToFit(atMost: 1) }
            arrived(cards)
        }
    }
}
#endif
