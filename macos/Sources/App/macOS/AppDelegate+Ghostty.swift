import AppKit

// MARK: Ghostty Delegate

/// This implements the Ghostty app delegate protocol which is used by the Ghostty
/// APIs for app-global information.
extension AppDelegate: Ghostty.Delegate {
    func ghosttySurface(id: UUID) -> Ghostty.SurfaceView? {
        for controller in BaseTerminalController.everyController {
            for surface in controller.surfaceTree where surface.id == id {
                return surface
            }
        }

        return nil
    }
}
