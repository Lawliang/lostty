#if os(macOS)
import AppKit

/// A card dragged by its title bar with the pointer off the canvas for
/// `CanvasDrop.holdSeconds` becomes a window again (Move to Window), its
/// title bar under the pointer: CanvasDrop the other way. While the
/// pointer's off the canvas the card holds still, and the countdown shows
/// over it and over the canvas, "Unmerging…"; bringing the pointer back or
/// letting go first leaves it a card.
@MainActor
final class CanvasUnmerge {
    static let shared = CanvasUnmerge()

    private weak var card: CardController?
    private weak var canvas: CanvasController?
    /// When the pointer went off the canvas; nil while it's on it.
    private var since: Date?
    private var timer: Timer?
    private var wells: [NSPanel] = []

    /// A drag of `card`'s title bar moved: whether the pointer's off the
    /// canvas, where the card holds still.
    func dragged(_ card: CardController, on canvas: CanvasController) -> Bool {
        guard let window = canvas.window else { return false }
        let off = !window.frame.contains(NSEvent.mouseLocation)
        if off, since == nil {
            begin(card, on: canvas, window: window)
        } else if !off, since != nil {
            cancel()
        }
        return off
    }

    /// The drag ended, or came back onto the canvas.
    func cancel() {
        timer?.invalidate()
        timer = nil
        since = nil
        card = nil
        canvas = nil
        CanvasDrop.hide(wells)
        wells = []
    }

    private func begin(_ card: CardController, on canvas: CanvasController, window: NSWindow) {
        self.card = card
        self.canvas = canvas
        since = Date()
        wells = [CanvasDrop.countdown(over: window.frame, on: window, label: "Unmerging…")]
        if let view = canvas.views[card.id] {
            let shown = window.convertToScreen(view.convert(view.bounds, to: nil)).intersection(window.frame)
            if !shown.isEmpty { wells.append(CanvasDrop.countdown(over: shown, on: window, label: "Unmerging…")) }
        }
        // The pointer may hold still off the canvas, sending no drags.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { CanvasUnmerge.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return cancel() }
        guard let card, let canvas, CanvasDrop.held(since: since, now: Date()) else { return }
        let point = NSEvent.mouseLocation
        cancel()
        canvas.moveToWindow(card, under: point)
    }
}
#endif
