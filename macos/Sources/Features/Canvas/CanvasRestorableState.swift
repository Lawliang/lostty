#if os(macOS)
import Foundation

/// The canvas in the app's restorable state, beside the Quick Terminal's,
/// under its own keys so neither overwrites the other. Decoding it makes
/// the panes, which reattach to their tmux sessions as a restored window's
/// do.
struct CanvasRestorableState: TerminalRestorable {
    static var selfKey: String { "canvasState" }
    static var versionKey: String { "canvasVersion" }
    static var version: Int { 1 }

    var saved: CanvasSaved<SplitTree<Ghostty.SurfaceView>>

    init(saved: CanvasSaved<SplitTree<Ghostty.SurfaceView>>) {
        self.saved = saved
    }

    init(copy other: CanvasRestorableState) {
        self = other
    }
}
#endif
