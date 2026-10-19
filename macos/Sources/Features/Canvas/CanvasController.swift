#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Lostty Beta's canvas: one window that is an infinite whiteboard of
/// terminal cards. Owns the window, the cards' layout (CanvasModel) and
/// the cards (CardController, one per split group). Closing the window
/// hides it; its terminals keep running.
@MainActor
final class CanvasController: NSWindowController, NSWindowDelegate {
    /// The app's one canvas, made the first time it's opened or restored.
    /// Set only by `show(_:freshCard:)` and `restore(_:state:)`.
    static var shared: CanvasController?

    /// The canvas while it's the key window: where ⌘N makes a card.
    static var key: CanvasController? {
        shared.flatMap { $0.window?.isKeyWindow == true ? $0 : nil }
    }

    /// Every card's controller, for the app's pane lookups.
    nonisolated static var allCards: [CardController] {
        onMain { shared?.cards ?? [] }
    }

    /// Closed cards kept so Undo can bring one back.
    static let retiredLimit = 10

    let ghostty: Ghostty.App
    private(set) var model = CanvasModel()
    /// In the order they were added; `model.cards` has them back to front.
    private(set) var cards: [CardController] = []
    /// The card holding keyboard focus, or that last held it.
    private(set) weak var focusedCard: CardController?
    /// The title bar's pill follows the focused card's pane. (Each card has
    /// its own icon row and usage bar.)
    let sidebar = ExtensionSidebarModel()

    private let surface = CanvasSurfaceView()
    var scrollView: CanvasScrollView { surface.scrollView }
    private(set) var views: [UUID: CardView] = [:]
    /// Closed cards with where they were, newest last, for Undo.
    private var retired: [(card: CardController, frame: CGRect)] = []
    /// Cards whose panes are moving to a window: gone for good, not for Undo.
    private var moving: Set<UUID> = []
    /// The zoom the terminals last rendered at.
    var settledZoom: CGFloat = 1
    var settleWork: DispatchWorkItem?
    var waits = CanvasWaits()
    /// The view to show when the window first opens (a restored canvas's).
    var pendingView: (center: CGPoint, zoom: CGFloat)?
    /// Whether the view was set the first time the window showed.
    private(set) var placed = false
    private var eventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    /// Opens the canvas, making it the first time; an empty canvas gets a
    /// fresh card unless panes are about to move in.
    @discardableResult
    static func show(_ ghostty: Ghostty.App, freshCard: Bool = true) -> CanvasController {
        let canvas = shared ?? CanvasController(ghostty)
        shared = canvas
        canvas.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if freshCard, canvas.cards.isEmpty { canvas.newCard() }
        return canvas
    }

    init(_ ghostty: Ghostty.App) {
        self.ghostty = ghostty
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Canvas"
        window.tabbingMode = .disallowed
        // Saved with the app's own state (CanvasRestorableState): window
        // restoration skips hidden windows, and a hidden canvas still holds
        // running terminals.
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)
        window.delegate = self
        let surface = surface
        window.contentView = NSHostingView(rootView: CanvasSurface(view: surface))
        if !window.setFrameUsingName("LosttyCanvas") { window.center() }
        window.setFrameAutosaveName("LosttyCanvas")
        installTitleAccessory()
        observe()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        placeIfNeeded()
        updateVisibility()
    }

    /// The first time the window shows (by ⌃⌘K, or a pane brought forward):
    /// lay out, then show the restored view or the middle.
    private func placeIfNeeded() {
        guard !placed, window?.isVisible == true else { return }
        placed = true
        window?.contentView?.layoutSubtreeIfNeeded()
        let view = pendingView ?? (CanvasModel.middle, 1)
        pendingView = nil
        scrollView.magnification = CanvasZoom.clamped(view.zoom)
        center(on: view.center)
        settleZoom()
    }

    private func installTitleAccessory() {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        let host = NSHostingView(rootView: CanvasTitleAccessory(sidebar: sidebar) { [weak self] in self?.jump() })
        host.frame.size = NSSize(width: 340, height: 28)
        accessory.view = host
        window?.addTitlebarAccessoryViewController(accessory)
    }

    private func observe() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(canvasMoved), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        // Focus follows the window's first responder: whichever card holds
        // it is the focused card.
        window?.publisher(for: \.firstResponder)
            .sink { [weak self] responder in self?.firstResponderChanged(responder) }
            .store(in: &cancellables)
        ClaudeRuntime.shared.$awaiting
            .sink { [weak self] awaiting in self?.waits.update(awaiting: awaiting, now: Date()) }
            .store(in: &cancellables)
        // A terminal has no use for pinches, so pinching anywhere zooms the
        // canvas; ⌥-scrolling pans it even over a terminal.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
            guard let self, event.window === window else { return event }
            if event.type == .magnify {
                scrollView.magnify(with: event)
                return nil
            }
            if event.modifierFlags.contains(.option) {
                scrollView.scrollWheel(with: event)
                return nil
            }
            return event
        }
    }

    // MARK: Cards

    /// A new card with one fresh terminal, in the middle of the view.
    @discardableResult
    func newCard(baseConfig: Ghostty.SurfaceConfiguration? = nil) -> CardController {
        let card = CardController(ghostty, canvas: self, baseConfig: baseConfig)
        add(card, frame: model.placement(in: scrollView.documentVisibleRect))
        focus(card)
        return card
    }

    /// A card holding `tree`: panes moved in from a window, or restored.
    @discardableResult
    func addCard(
        tree: SplitTree<Ghostty.SurfaceView>, frame: CGRect? = nil, focused: Ghostty.SurfaceView? = nil
    ) -> CardController {
        let card = CardController(ghostty, canvas: self, tree: tree)
        if let focused, tree.contains(focused) {
            card.focusedSurface = focused
            card.sidebar.focusedSurfaceID = focused.id
        }
        add(card, frame: frame ?? model.placement(size: Self.cardSize(for: tree), in: scrollView.documentVisibleRect))
        return card
    }

    /// Big enough for `tree`'s panes as they were last laid out, plus a header.
    static func cardSize(for tree: SplitTree<Ghostty.SurfaceView>) -> CGSize {
        let panes = tree.viewBounds()
        guard panes.width > 0, panes.height > 0 else { return CanvasModel.newCardSize }
        return CGSize(width: panes.width, height: panes.height + CardView.chromeHeight)
    }

    private func add(_ card: CardController, frame: CGRect) {
        cards.append(card)
        model.add(card.id, frame: frame)
        let view = CardView(card: card, canvas: self)
        view.stackIndex = model.cards.count - 1
        views[card.id] = view
        scrollView.document.addSubview(view)
        if let placed = model.card(card.id)?.frame { view.frame = placed }
        updateVisibility()
        saveSoon()
        for surface in card.surfaceTree { surface.canvasZoomDidSettle(settledZoom) }
    }

    func card(holding surface: Ghostty.SurfaceView) -> CardController? {
        cards.first { $0.surfaceTree.contains(surface) }
    }

    /// Keyboard focus to `card`'s focused pane.
    func focus(_ card: CardController) {
        guard let surface = card.focusedSurface ?? card.surfaceTree.first else { return }
        card.focusSurface(surface)
    }

    private func firstResponderChanged(_ responder: NSResponder?) {
        guard let surface = responder as? Ghostty.SurfaceView, let card = card(holding: surface) else { return }
        card.focusedSurfaceDidChange(to: surface)
    }

    /// A card's pane is taking keyboard focus: the card is the focused one
    /// from now on (before its pane is, so the pane never blinks unfocused),
    /// in front.
    func cardWillFocus(_ card: CardController) {
        let previous = focusedCard
        focusedCard = card
        guard previous !== card else { return }
        previous?.syncFocusToSurfaceTree()
        bringToFront(card)
    }

    /// A card's pane took keyboard focus: the window's title, icon row and
    /// outline follow it.
    func cardDidFocus(_ card: CardController) {
        card.syncFocusToSurfaceTree()
        card.applyTitleToWindow()
        sidebar.focusedSurfaceID = card.focusedSurface?.id
        for (id, view) in views { view.isFocusedCard = id == card.id }
    }

    private func bringToFront(_ card: CardController) {
        model.bringToFront(card.id)
        for (index, entry) in model.cards.enumerated() { views[entry.id]?.stackIndex = index }
        // Reorders without taking views out of the window, so the focused
        // pane keeps keyboard focus.
        scrollView.document.sortSubviews({ a, b, _ in
            let left = (a as? CardView)?.stackIndex ?? 0, right = (b as? CardView)?.stackIndex ?? 0
            return left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
        }, context: nil)
    }

    /// Moving or resizing, live.
    func setFrame(_ frame: CGRect, of card: CardController) {
        model.setFrame(frame, of: card.id)
        if let frame = model.card(card.id)?.frame { views[card.id]?.frame = frame }
    }

    /// A drag or resize ended.
    func cardFrameDidSettle() {
        updateVisibility()
        saveSoon()
    }

    /// A card's panes changed. With none left the card goes, kept a while
    /// for Undo; when Undo gives it its panes back, it returns where it was.
    func cardTreeDidChange(_ card: CardController, from old: SplitTree<Ghostty.SurfaceView>, to new: SplitTree<Ghostty.SurfaceView>) {
        if new.isEmpty {
            retire(card)
        } else if old.isEmpty, let index = retired.firstIndex(where: { $0.card === card }) {
            let frame = retired.remove(at: index).frame
            add(card, frame: frame)
            focus(card)
        }
        updateVisibility()
        saveSoon()
        for surface in card.surfaceTree { surface.canvasZoomDidSettle(settledZoom) }
    }

    private func retire(_ card: CardController) {
        guard let frame = model.card(card.id)?.frame else { return }
        model.remove(card.id)
        cards.removeAll { $0 === card }
        views.removeValue(forKey: card.id)?.removeFromSuperview()
        if !moving.contains(card.id) {
            retired.append((card, frame))
            if retired.count > Self.retiredLimit { retired.removeFirst() }
        }
        guard focusedCard === card else { return }
        focusedCard = nil
        guard let next = model.cards.last.flatMap({ entry in cards.first { $0.id == entry.id } }) else { return }
        // A card closing while you work elsewhere never pulls the canvas forward.
        if window?.isKeyWindow == true {
            focus(next)
        } else {
            cardWillFocus(next)
            cardDidFocus(next)
        }
    }

    /// Shows the canvas and pans just enough to bring `card` into view.
    func reveal(_ card: CardController) {
        if window?.isVisible != true { showWindow(nil) }
        guard let view = views[card.id] else { return }
        view.scrollToVisible(view.bounds)
    }

    /// Move to Window: the card's panes become a normal window; nothing restarts.
    /// The card's undo history goes with it: undoing a split it made would
    /// pull the window's panes back into a second card.
    func moveToWindow(_ card: CardController) {
        let tree = card.surfaceTree
        guard !tree.isEmpty else { return }
        let undo = (NSApp.delegate as? AppDelegate)?.undoManager
        undo?.removeAllActions(withTarget: card)
        moving.insert(card.id)
        card.surfaceTree = .init()
        moving.remove(card.id)
        // No "Undo New Window" either: undoing it would close the moved panes.
        if let undo {
            undo.disableUndoRegistration { _ = TerminalController.newWindow(ghostty, tree: tree) }
        } else {
            _ = TerminalController.newWindow(ghostty, tree: tree)
        }
    }

    // MARK: View

    @objc private func canvasMoved() {
        updateVisibility()
        saveSoon()
        guard scrollView.magnification != settledZoom else { return }
        // While the zoom moves the panes keep their pixels (the compositor
        // scales them) and their grid; they re-render once it settles.
        for card in cards {
            for surface in card.surfaceTree where !surface.canvasZoomInFlight { surface.canvasZoomInFlight = true }
        }
        scheduleSettle()
    }

    private func center(on point: CGPoint) {
        let size = scrollView.contentView.bounds.size
        scrollView.contentView.scroll(to: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// ⌃⌘0: every card in view.
    func zoomToFit() {
        guard let rect = model.fitRect else { return }
        scrollView.magnify(toFit: rect)
        settleZoom()
    }

    /// ⌃⌘1, double-clicking a header, the green button: `card` centered at
    /// `zoom` (100%).
    func zoom(to card: CardController, zoom: CGFloat = 1) {
        guard let frame = model.card(card.id)?.frame else { return }
        scrollView.magnify(toFit: CanvasZoom.rect(
            centeredOn: CGPoint(x: frame.midX, y: frame.midY), zoom: zoom, viewport: scrollView.contentSize))
        settleZoom()
    }

    /// The zoom stopped changing: the terminals re-render at it.
    func settleZoom() {
        settleWork?.cancel()
        settledZoom = scrollView.magnification
        for card in cards {
            for surface in card.surfaceTree { surface.canvasZoomDidSettle(settledZoom) }
        }
        updateVisibility()
        saveSoon()
    }

    /// Which cards draw: only those near the view, and none while the
    /// canvas is hidden or covered.
    func updateVisibility() {
        let shown = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        let inView = model.cardsInView(scrollView.documentVisibleRect)
        for card in cards {
            views[card.id]?.mode = shown && inView.contains(card.id) ? .live : .hidden
        }
    }

    /// The app saves its restorable state (and the canvas with it) soon.
    func saveSoon() {
        NSApp.invalidateRestorableState()
    }

    // MARK: NSWindowDelegate

    /// Closing the canvas hides it; its terminals keep running.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        updateVisibility()
        saveSoon()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        placeIfNeeded()
        // Only the focused card restores keyboard focus to its pane.
        focusedCard?.windowDidBecomeKey(notification)
        for card in cards where card !== focusedCard { card.syncFocusToSurfaceTree() }
    }

    func windowDidResignKey(_ notification: Notification) {
        for card in cards { card.windowDidResignKey(notification) }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        placeIfNeeded()
        updateVisibility()
    }

    func windowDidResize(_ notification: Notification) {
        updateVisibility()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (NSApp.delegate as? AppDelegate)?.undoManager
    }
}
#endif
