#if os(macOS)
import AppKit
import Combine
import GhosttyKit
import SwiftUI

/// A card on the canvas, a small Lostty window: a Mac window's title bar,
/// corners, edge and shadow, its panes with their own bottom bar (the
/// window's own TerminalView, so splits and Ready for Response come with
/// it), resize handles on its edges, and the Window Light round it. Puts
/// its card's controller in the responder chain, so menu actions reach the
/// card.
final class CardView: NSView, CanvasStacked {
    /// A standard title bar's height.
    static let headerHeight = ClaudeUsageBar.height
    /// The header and bottom bar: a card's height past its panes'.
    static let chromeHeight = headerHeight + ClaudeUsageBar.height
    static let cornerRadius: CGFloat = 10

    /// Live: the terminals draw. Hidden: out of view or the canvas is; the
    /// terminals pause.
    enum Mode { case live, hidden }

    let card: CardController
    private weak var canvas: CanvasController?
    /// Everything but the resize handles, clipped to the corners; the card
    /// itself draws the shadow outside them.
    private let content = CardContentView()
    private let header: CardHeaderView
    private let terminal: CardTerminalHost
    private var handles: [CardEdgeHandle] = []
    /// Back-to-front position among the canvas's cards.
    var stackIndex = 0
    private var chrome: AnyCancellable?

    var mode: Mode = .live {
        didSet { if mode != oldValue { applyMode() } }
    }

    /// The focused card is the active window: colored buttons, a deeper
    /// shadow. The others look like inactive windows.
    var isFocusedCard = false {
        didSet {
            needsDisplay = true
            header.buttons.isActive = isFocusedCard
        }
    }

    init(card: CardController, canvas: CanvasController) {
        self.card = card
        self.canvas = canvas
        header = CardHeaderView(card: card, canvas: canvas)
        terminal = CardTerminalHost(rootView: CardTerminal(card: card))
        terminal.card = card
        super.init(frame: .zero)
        Self.setUpWindowLook(self, content: content)
        addSubview(content)
        content.addSubview(terminal)
        content.addSubview(header)
        header.buttons.isActive = false
        for edges in CanvasModel.handleEdges {
            let handle = CardEdgeHandle(edges: edges, id: card.id, canvas: canvas) { [weak card] in card?.holdGrids($0) }
            handles.append(handle)
            addSubview(handle)
        }
        // Light or dark to suit the skin, as a window's title bar is.
        chrome = card.sidebar.$chromeColor.sink { [weak self] color in
            self?.appearance = color.map { NSAppearance(named: $0.isLightColor ? .aqua : .darkAqua) } ?? nil
            self?.header.needsDisplay = true
            self?.header.buttons.needsDisplay = true
            self?.needsDisplay = true
            // Behind the panes: fills any sliver a held or zoomed grid leaves.
            self?.content.layer?.backgroundColor = color?.cgColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        Self.updateWindowLook(self, content: content, focused: isFocusedCard)
    }

    /// A card's rounded corners (its `content` clipped to them) and shadow,
    /// a ticket's too.
    static func setUpWindowLook(_ card: NSView, content: NSView) {
        card.wantsLayer = true
        card.layer?.masksToBounds = false
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOffset = CGSize(width: 0, height: -6)
        content.wantsLayer = true
        content.layer?.cornerRadius = cornerRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
    }

    /// A Mac window's hairline edge, white on the active card, and its
    /// shadow: deeper on the active one.
    static func updateWindowLook(_ card: NSView, content: NSView, focused: Bool) {
        let dark = card.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let edge = focused ? NSColor.white : dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.22)
        content.layer?.borderColor = edge.cgColor
        content.layer?.borderWidth = 0.5
        card.layer?.shadowOpacity = focused ? 0.45 : 0.25
        card.layer?.shadowRadius = focused ? 18 : 8
    }

    override func layout() {
        super.layout()
        content.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        terminal.frame = NSRect(x: 0, y: Self.headerHeight, width: bounds.width, height: max(0, bounds.height - Self.headerHeight))
        for handle in handles { handle.frame = CanvasModel.handleFrame(for: handle.edges, in: bounds) }
    }

    /// A click on the card's SwiftUI controls while the canvas is zoomed
    /// (see CardTerminalHost) zooms to the card at 100%, where they take
    /// clicks.
    override func mouseDown(with event: NSEvent) {
        canvas?.focus(card)
        canvas?.zoom(to: card)
    }

    /// The card's controller answers menu actions (Split Right, Close…) for
    /// its panes, as a window's controller does for a window's.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        card.nextResponder = superview
        nextResponder = card
    }

    private func applyMode() {
        // The panes stay shown, so a focused pane out of view keeps keyboard
        // focus instead of AppKit handing it on.
        // What a hidden window's panes get: no drawing until shown again.
        for view in card.surfaceTree {
            if let surface = view.surface { ghostty_surface_set_occlusion(surface, mode == .live) }
        }
    }
}

/// The canvas's views that stack: a terminal card's and a ticket's.
protocol CanvasStacked: AnyObject {
    /// Back-to-front position among the canvas's cards.
    var stackIndex: Int { get set }
}

/// A card's contents, laid out top-down as the card is.
final class CardContentView: NSView {
    override var isFlipped: Bool { true }
}

/// A card's panes and bottom bar: the window's terminal view.
struct CardTerminal: View {
    let card: CardController

    var body: some View {
        TerminalView(
            ghostty: card.ghostty, viewModel: card, delegate: card, extensionSidebar: card.sidebar, showsWhatsNew: false)
            .environment(\.splitDragChanged) { [weak card] dragging in card?.holdGrids(dragging) }
    }
}

/// Hosts a card's panes and bottom bar. While the canvas is zoomed
/// (an ancestor is magnified) SwiftUI finds the wrong spot for a click (its
/// hit test is off by the zoom) and drops clicks on its own controls
/// (spike check S5, and the apps): so then a click in a pane goes to
/// that pane, and any other goes to the card, which zooms to 100%.
final class CardTerminalHost: NSHostingView<CardTerminal> {
    weak var card: CardController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // At 100% SwiftUI finds its panes itself, and its own controls over
        // them (search bar, dividers, grab handle) must keep their clicks.
        guard let card, let superview, (enclosingScrollView?.magnification ?? 1) != 1 else {
            return super.hitTest(point)
        }
        guard frame.contains(point) else { return nil }
        for pane in card.surfaceTree where !pane.isHiddenOrHasHiddenAncestor {
            if pane.bounds.contains(pane.convert(point, from: superview)) { return pane }
        }
        return enclosingCardView
    }

    /// Zoomed, SwiftUI's own accessibility hit test loops until the stack
    /// runs out, and Lostty crashes, when an accessibility app (Rectangle
    /// asks on every click) asks what's under a point off the panes, the
    /// bottom bar's. So zoomed, a pane answers for itself and the rest of
    /// the card is this one element, as clicks there go to the card.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard let card, let window, (enclosingScrollView?.magnification ?? 1) != 1 else {
            return super.accessibilityHitTest(point)
        }
        let inWindow = window.convertPoint(fromScreen: point)
        for pane in card.surfaceTree where !pane.isHiddenOrHasHiddenAncestor {
            if pane.bounds.contains(pane.convert(inWindow, from: nil)) { return pane }
        }
        return self
    }

    private var enclosingCardView: CardView? {
        var view = superview
        while let next = view, !(next is CardView) { view = next.superview }
        return view as? CardView
    }
}

/// A strip along a card's edge, or a square at its corner, that resizes
/// the card by dragging.
final class CardEdgeHandle: NSView {
    let edges: CanvasModel.Edges
    private let id: UUID
    private weak var canvas: CanvasController?
    /// Told when a drag starts and ends (a terminal card holds its grids).
    private let hold: (Bool) -> Void
    private var start: (point: CGPoint, frame: CGRect)?

    init(edges: CanvasModel.Edges, id: UUID, canvas: CanvasController, hold: @escaping (Bool) -> Void = { _ in }) {
        self.edges = edges
        self.id = id
        self.canvas = canvas
        self.hold = hold
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.cursor(for: edges))
    }

    /// A window's resize cursor for the edge or corner: diagonal at the
    /// corners from macOS 15 (a crosshair before).
    static func cursor(for edges: CanvasModel.Edges) -> NSCursor {
        guard #available(macOS 15, *) else {
            return switch edges {
            case .left, .right: .resizeLeftRight
            case .top, .bottom: .resizeUpDown
            default: .crosshair
            }
        }
        let position: NSCursor.FrameResizePosition = switch edges {
        case .left: .left
        case .right: .right
        case .top: .top
        case .bottom: .bottom
        case [.left, .top]: .topLeft
        case [.right, .top]: .topRight
        case [.left, .bottom]: .bottomLeft
        default: .bottomRight
        }
        return .frameResize(position: position, directions: .all)
    }

    override func mouseDown(with event: NSEvent) {
        guard let frame = canvas?.model.card(id)?.frame, let point = documentPoint(event) else { return }
        start = (point, frame)
        hold(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas, let start, let point = documentPoint(event) else { return }
        let delta = CGSize(width: point.x - start.point.x, height: point.y - start.point.y)
        canvas.setFrame(CanvasModel.resized(start.frame, edges: edges, by: delta), of: id)
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        hold(false)
        canvas?.cardFrameDidSettle()
    }

    /// Where `event` is on the canvas document, however zoomed.
    private func documentPoint(_ event: NSEvent) -> CGPoint? {
        enclosingScrollView?.documentView?.convert(event.locationInWindow, from: nil)
    }
}

/// A hosting view that never takes clicks, so they reach the view under it.
/// Zoomed, it's one accessibility element, as SwiftUI's own accessibility
/// hit test loops until Lostty crashes (CardTerminalHost).
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        (enclosingScrollView?.magnification ?? 1) != 1 ? self : super.accessibilityHitTest(point)
    }
}
#endif
