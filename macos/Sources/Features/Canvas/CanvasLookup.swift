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
