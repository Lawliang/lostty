#if os(macOS)
import AppKit
import GhosttyKit
import SwiftUI

/// A card on the canvas: its header, its panes (the window's own
/// TerminalView, so splits and Ready for Response come with it), resize
/// handles on its edges, its tile for zooming far out, and the Window Light
/// round it. Puts its card's controller in the responder chain, so menu
/// actions reach the card.
final class CardView: NSView {
    static let headerHeight: CGFloat = 24
    static let cornerRadius: CGFloat = 8

    /// Live: the terminals draw. Tile: a status tile instead (zoomed far
    /// out). Hidden: out of view or the canvas is; the terminals pause.
    enum Mode { case live, tile, hidden }

    let card: CardController
    private let header: CardHeaderView
    private let terminal: CardTerminalHost
    private let tile: NSHostingView<CardTile>
    private let trace: CardTraceHost
    private var handles: [CardEdgeHandle] = []
    /// Back-to-front position among the canvas's cards.
    var stackIndex = 0

    var mode: Mode = .live {
        didSet { if mode != oldValue { applyMode() } }
    }

    var isFocusedCard = false {
        didSet { needsDisplay = true }
    }

    init(card: CardController, canvas: CanvasController) {
        self.card = card
        header = CardHeaderView(card: card, canvas: canvas)
        terminal = CardTerminalHost(rootView: CardTerminal(card: card))
        terminal.card = card
        let open: () -> Void = { [weak canvas, weak card] in
            if let canvas, let card { canvas.zoom(to: card) }
        }
        tile = NSHostingView(rootView: CardTile(card: card, zoom: canvas.settledZoom, open: open))
        trace = CardTraceHost(card: card)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        addSubview(terminal)
        addSubview(tile)
        addSubview(header)
        addSubview(trace)
        for edges in CanvasModel.handleEdges {
            let handle = CardEdgeHandle(edges: edges, card: card, canvas: canvas)
            handles.append(handle)
            addSubview(handle)
        }
        tile.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    /// The focused card has an accent outline; the others a hairline.
    override func updateLayer() {
        layer?.borderColor = (isFocusedCard ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.borderWidth = isFocusedCard ? 1 : 0.5
    }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        terminal.frame = NSRect(x: 0, y: Self.headerHeight, width: bounds.width, height: max(0, bounds.height - Self.headerHeight))
        tile.frame = bounds
        trace.frame = bounds
        for handle in handles { handle.frame = CanvasModel.handleFrame(for: handle.edges, in: bounds) }
    }

    /// The card's controller answers menu actions (Split Right, Close…) for
    /// its panes, as a window's controller does for a window's.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        card.nextResponder = superview
        nextResponder = card
    }

    /// The canvas's zoom settled: the tile keeps its text readable at it.
    func zoomDidSettle(_ zoom: CGFloat) {
        tile.rootView = CardTile(card: card, zoom: zoom, open: tile.rootView.open)
    }

    private func applyMode() {
        // The panes stay in the window (the tile covers them), so a hidden
        // focused pane keeps keyboard focus instead of AppKit handing it on.
        tile.isHidden = mode != .tile
        header.isHidden = mode == .tile
        trace.isLit = mode == .live
        // What a hidden window's panes get: no drawing until shown again.
        for view in card.surfaceTree {
            if let surface = view.surface { ghostty_surface_set_occlusion(surface, mode == .live) }
        }
    }
}

/// A card's panes: the window's terminal view without the icon row and
/// usage bar (the canvas has one for all its cards). The panes leave the
/// Window Light to the card.
struct CardTerminal: View {
    let card: CardController

    var body: some View {
        TerminalView(ghostty: card.ghostty, viewModel: card, delegate: card)
            .environment(\.hostsWindowTrace, true)
    }
}

/// Hosts a card's panes. SwiftUI misses its panes when the canvas is
/// zoomed (an ancestor is magnified): a click it keeps for itself that
/// falls inside a pane goes to the pane (spike check S5).
final class CardTerminalHost: NSHostingView<CardTerminal> {
    weak var card: CardController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // At 100% SwiftUI finds its panes itself, and its own controls over
        // them (search bar, dividers, grab handle) must keep their clicks.
        guard hit === self, let card, let superview,
              (enclosingScrollView?.magnification ?? 1) != 1 else { return hit }
        for pane in card.surfaceTree where !pane.isHiddenOrHasHiddenAncestor {
            if pane.bounds.contains(pane.convert(point, from: superview)) { return pane }
        }
        return hit
    }
}

/// A strip along a card's edge, or a square at its corner, that resizes
/// the card by dragging.
final class CardEdgeHandle: NSView {
    let edges: CanvasModel.Edges
    private let card: CardController
    private weak var canvas: CanvasController?
    private var start: (point: CGPoint, frame: CGRect)?

    init(edges: CanvasModel.Edges, card: CardController, canvas: CanvasController) {
        self.edges = edges
        self.card = card
        self.canvas = canvas
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resetCursorRects() {
        let cursor: NSCursor = switch edges {
        case .left, .right: .resizeLeftRight
        case .top, .bottom: .resizeUpDown
        default: .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let frame = canvas?.model.card(card.id)?.frame, let point = documentPoint(event) else { return }
        start = (point, frame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start, let point = documentPoint(event) else { return }
        let delta = CGSize(width: point.x - start.point.x, height: point.y - start.point.y)
        canvas.setFrame(CanvasModel.resized(start.frame, edges: edges, by: delta), of: card)
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        canvas?.cardFrameDidSettle()
    }

    /// Where `event` is on the canvas document, however zoomed.
    private func documentPoint(_ event: NSEvent) -> CGPoint? {
        enclosingScrollView?.documentView?.convert(event.locationInWindow, from: nil)
    }
}

/// The Window Light round a card: the website's light while Claude works
/// in one of its panes and Lostty → Claude Trace Style is Window Light
/// (Skin Traces stay on the panes' own edges). Only while the card draws
/// live; out of view it stops animating altogether.
final class CardTraceHost: NSView {
    private let card: CardController
    private let edge = WindowTraceEdge()
    private var host: NSHostingView<WindowTraceView>?

    var isLit = true {
        didSet { if isLit != oldValue { update() } }
    }

    init(card: CardController) {
        self.card = card
        super.init(frame: .zero)
        edge.cornerRadius = CardView.cornerRadius
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func update() {
        if isLit, host == nil {
            let host = NSHostingView(rootView: WindowTraceView(controller: card, sidebar: card.header, edge: edge))
            host.frame = bounds
            host.autoresizingMask = [.width, .height]
            addSubview(host)
            self.host = host
        } else if !isLit {
            host?.removeFromSuperview()
            host = nil
        }
    }
}

/// A hosting view that never takes clicks, so they reach the view under it.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
