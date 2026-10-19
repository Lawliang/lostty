#if os(macOS)
import AppKit
import GhosttyKit

/// One card on the canvas: a split group run exactly as a window's panes
/// are (splits, closing, focus, zoom, undo, close confirmations), by the
/// same base controller. It has no window of its own: `window` is the
/// canvas's, whose delegate (CanvasController) passes on what a card needs
/// to hear, and the card sits in the responder chain under its view.
final class CardController: BaseTerminalController {
    let id = UUID()
    private(set) weak var canvas: CanvasController?
    /// The card's focused pane, for its header's pill and its light.
    let header = ExtensionSidebarModel()

    init(
        _ ghostty: Ghostty.App, canvas: CanvasController,
        tree: SplitTree<Ghostty.SurfaceView>? = nil, baseConfig: Ghostty.SurfaceConfiguration? = nil
    ) {
        self.canvas = canvas
        super.init(ghostty, baseConfig: baseConfig, surfaceTree: tree)
        // As in a new window, the first pane starts focused.
        focusedSurface = surfaceTree.first
        header.focusedSurfaceID = focusedSurface?.id
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The canvas window: close confirmations, key state and the title come
    /// from it. Setting it does nothing; a card owns no window.
    override var window: NSWindow? {
        get { canvas?.window }
        set {}
    }

    /// Whether a card's pane has keyboard focus: the canvas is key, it's the
    /// canvas's focused card, no command palette covers it, and it's the
    /// card's focused pane. At most one pane on the canvas passes.
    static func paneIsFocused(windowIsKey: Bool, cardIsFocused: Bool, paletteShowing: Bool, isFocusedPane: Bool) -> Bool {
        windowIsKey && cardIsFocused && !paletteShowing && isFocusedPane
    }

    var isFocusedCard: Bool { canvas?.focusedCard === self }

    override func syncFocusToSurfaceTree() {
        for surfaceView in surfaceTree {
            surfaceView.focusDidChange(Self.paneIsFocused(
                windowIsKey: window?.isKeyWindow ?? false, cardIsFocused: isFocusedCard,
                paletteShowing: commandPaletteIsShowing, isFocusedPane: surfaceView == focusedSurface))
        }
    }

    /// Every card's view hears the window's focused pane; a card takes only
    /// its own, and then it is the canvas's focused card.
    override func focusedSurfaceDidChange(to surface: Ghostty.SurfaceView?) {
        guard let surface, surfaceTree.contains(surface) else { return }
        super.focusedSurfaceDidChange(to: surface)
        header.focusedSurfaceID = surface.id
        canvas?.cardDidFocus(self)
    }

    /// Panes added or gone: the canvas keeps, retires or brings back the card.
    override func surfaceTreeDidChange(from: SplitTree<Ghostty.SurfaceView>, to: SplitTree<Ghostty.SurfaceView>) {
        super.surfaceTreeDidChange(from: from, to: to)
        canvas?.cardTreeDidChange(self, from: from, to: to)
    }

    /// Only the focused card titles the canvas window.
    override func applyTitleToWindow() {
        guard isFocusedCard else { return }
        super.applyTitleToWindow()
    }

    override func pwdDidChange(to: URL?) {
        guard isFocusedCard else { return }
        super.pwdDidChange(to: to)
    }

    /// Step resizing would size the whole canvas window to one card's cells.
    override func cellSizeDidChange(to: NSSize) {}

    /// Bringing a pane forward (a notification, Branches, Jump) shows its
    /// card first.
    override func focusSurface(_ view: Ghostty.SurfaceView) {
        if surfaceTree.contains(view) { canvas?.reveal(self) }
        super.focusSurface(view)
    }

    /// ⇧⌘W closes the card, not the canvas.
    override func closeWindow(_ sender: Any) {
        closeCard()
    }

    /// Every pane, asking first when one runs something, as closing a window
    /// does. Undo brings the card back.
    func closeCard() {
        guard let root = surfaceTree.root else { return }
        closeSurface(root, withConfirmation: surfaceTree.contains(where: { $0.needsConfirmQuit }))
    }
}
#endif
