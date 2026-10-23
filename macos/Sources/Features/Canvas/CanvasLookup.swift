#if os(macOS)
import AppKit

extension BaseTerminalController {
    /// Every terminal controller: each window's (the Quick Terminal's too)
    /// and each canvas card's.
    nonisolated static var everyController: [BaseTerminalController] {
        CanvasController.onMain {
            NSApp.windows.compactMap { $0.windowController as? BaseTerminalController } + CanvasController.allCards
        }
    }
}

extension Ghostty.SurfaceView {
    /// The controller whose split tree holds this pane: its canvas card's,
    /// else its window's.
    nonisolated var terminalController: BaseTerminalController? {
        CanvasController.onMain {
            CanvasController.shared?.card(holding: self) ?? window?.windowController as? BaseTerminalController
        }
    }

    /// Whether a click at `point` (in its window) is on this pane, not on a
    /// card in front of the pane's own, nor on the + menu or a notification
    /// over the cards. Always true off the canvas, where panes never overlap.
    nonisolated func isUncoveredByCards(at point: NSPoint) -> Bool {
        CanvasController.onMain {
            guard let canvas = CanvasController.shared, let card = canvas.card(holding: self) else { return true }
            guard !canvas.floats(at: point) else { return false }
            return canvas.model.card(at: canvas.scrollView.document.convert(point, from: nil)) == card.id
        }
    }
}

extension CanvasController {
    /// Runs `body` on the main thread from anywhere: the pane lookups run
    /// in Ghostty's action callbacks (main thread, not marked for the main
    /// actor) and in notification callbacks (sometimes a background queue).
    nonisolated static func onMain<T>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
}
#endif
