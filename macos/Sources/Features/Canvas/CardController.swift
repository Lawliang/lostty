#if os(macOS)
import AppKit
import Combine
import GhosttyKit

/// One card on the canvas: a split group run exactly as a window's panes
/// are (splits, closing, focus, zoom, undo, close confirmations), by the
/// same base controller. It has no window of its own: `window` is the
/// canvas's, whose delegate (CanvasController) passes on what a card needs
/// to hear, and the card sits in the responder chain under its view.
final class CardController: BaseTerminalController {
    let id = UUID()
    private(set) weak var canvas: CanvasController?
    /// The card's own bottom bar (usage, or the apps), as a window has (no
    /// notifications: the canvas has one stack for every card); also what
    /// its header's pill and its light follow.
    let sidebar = ExtensionSidebarModel(notifications: false)
    private var appearanceCancellables: Set<AnyCancellable> = []

    init(
        _ ghostty: Ghostty.App, canvas: CanvasController,
        tree: SplitTree<Ghostty.SurfaceView>? = nil, baseConfig: Ghostty.SurfaceConfiguration? = nil
    ) {
        self.canvas = canvas
        super.init(ghostty, baseConfig: baseConfig, surfaceTree: tree)
        // As in a new window, the first pane starts focused.
        focusedSurface = surfaceTree.first
        sidebar.focusedSurfaceID = focusedSurface?.id
        // Closing a sidebar app hands keyboard focus back to the pane.
        sidebar.focusTerminal = { [weak self] in
            if let surface = self?.focusedSurface { Ghostty.moveFocus(to: surface) }
        }
        watchAppearance()
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
        canvas?.cardWillFocus(self)
        super.focusedSurfaceDidChange(to: surface)
        sidebar.focusedSurfaceID = surface.id
        watchAppearance()
        canvas?.cardDidFocus(self)
    }

    /// Panes added or gone: the canvas keeps, retires or brings back the card.
    override func surfaceTreeDidChange(from: SplitTree<Ghostty.SurfaceView>, to: SplitTree<Ghostty.SurfaceView>) {
        super.surfaceTreeDidChange(from: from, to: to)
        watchAppearance()
        canvas?.cardTreeDidChange(self, from: from, to: to)
    }

    /// The card's header and bottom bar take its panes' background,
    /// as a window's title bar does: the focused pane's when it borders the
    /// top, else the top-left pane's.
    override func syncAppearance() {
        sidebar.chromeColor = chromePane.map {
            NSColor($0.backgroundColor ?? $0.derivedConfig.backgroundColor).withAlphaComponent(1)
        }
    }

    private var chromePane: Ghostty.SurfaceView? {
        guard let root = surfaceTree.root else { return nil }
        if let focusedSurface, let node = root.node(view: focusedSurface),
           root.spatial().doesBorder(side: .up, from: node) {
            return focusedSurface
        }
        return root.leftmostLeaf()
    }

    /// Follows the chrome pane's colors as they change (a skin, a theme).
    private func watchAppearance() {
        appearanceCancellables.removeAll()
        syncAppearance()
        guard let pane = chromePane else { return }
        // The publishers fire before the change lands; look once it has.
        pane.$derivedConfig.map { _ in () }.merge(with: pane.$backgroundColor.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncAppearance() }
            .store(in: &appearanceCancellables)
    }

    /// The card's own title bar shows its title; only the focused card
    /// titles the canvas window.
    @Published private(set) var title = "Lostty"

    override func applyTitleToWindow() {
        title = windowTitle
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

    /// While the card's edge or one of its split dividers is dragged, its
    /// panes hold their grids; they resize once, on release.
    func holdGrids(_ hold: Bool) {
        for surface in surfaceTree { surface.canvasResizeHeld = hold }
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
