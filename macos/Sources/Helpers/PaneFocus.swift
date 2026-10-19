#if os(macOS)
import AppKit

@MainActor
enum PaneFocus {
    /// Brings pane `id`'s window to the front and focuses the pane. False
    /// when no window shows it any more.
    @discardableResult
    static func focus(_ id: UUID) -> Bool {
        guard let surface = (NSApp.delegate as? AppDelegate)?.findSurface(forUUID: id),
              let controller = surface.terminalController
        else { return false }
        NSApp.activate(ignoringOtherApps: true)
        surface.window?.makeKeyAndOrderFront(nil)
        controller.focusSurface(surface)
        return true
    }
}
#endif
