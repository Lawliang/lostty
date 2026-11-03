#if os(macOS)
import AppKit
import SwiftUI

/// The canvas's scroll view: two-finger scrolling pans it, over a card too
/// (but scrolls the focused pane over it; ⌥ swaps the two over a pane), in
/// any direction (not locked to the swipe's main axis), pinching or ⌘ and
/// scrolling zooms it 25%–200% (its clip view scales, so clicks still land
/// on the right cell), and it has no scrollers.
final class CanvasScrollView: NSScrollView {
    let document = CanvasDocumentView(frame: NSRect(x: 0, y: 0, width: CanvasModel.size, height: CanvasModel.size))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowsMagnification = true
        minMagnification = CanvasZoom.minimum
        maxMagnification = CanvasZoom.maximum
        hasHorizontalScroller = false
        hasVerticalScroller = false
        usesPredominantAxisScrolling = false
        drawsBackground = false
        contentView.drawsBackground = false
        contentView.postsBoundsChangedNotifications = true
        wantsLayer = true
        documentView = document
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The pane the scroll under way scrolls, or nil while it pans the
    /// canvas. Decided where the scroll starts, so a pane the canvas pans
    /// under the pointer doesn't take it over, nor does its momentum change.
    weak var scrollingPane: NSView?
    /// The tickets panel whose list the scroll under way scrolls (TicketBoardHost),
    /// or nil. Decided where the scroll starts, as `scrollingPane` is; the
    /// canvas never hands a scroll on to it.
    weak var scrollingTicket: NSView?

    /// A scroll gesture's first event, or a mouse wheel's click.
    static func startsScroll(_ event: NSEvent) -> Bool {
        event.phase.contains(.began) || (event.phase.isEmpty && event.momentumPhase.isEmpty)
    }

    /// How long after the canvas last panned a new scroll still pans it,
    /// over a pane or ticket list that would scroll: swipes in a row are
    /// one move of the view.
    static let panCarry: TimeInterval = 1
    private var lastPan: Date?

    /// Whether a scroll starting `now` carries on the pan before it.
    func panCarriesOn(now: Date = Date()) -> Bool {
        lastPan.map { now.timeIntervalSince($0) < Self.panCarry } ?? false
    }

    override func scrollWheel(with event: NSEvent) {
        if Self.startsScroll(event) {
            // Started over the canvas, or a pane or ticket handed it on: it
            // pans, or zooms with ⌘.
            scrollingPane = nil
            scrollingTicket = nil
            scrollZooming = event.modifierFlags.contains(.command)
        } else if let pane = scrollingPane {
            pane.scrollWheel(with: event)
            return
        }
        if scrollZooming {
            zooms(event)
            return
        }
        if pans(event) { return }
        super.scrollWheel(with: event)
    }

    /// Where the canvas is drawn while it isn't scrolled there yet (a
    /// trackpad pan under way, a glide): the visible rect's origin, in
    /// document points, and the zoom. The cards get there by a layer
    /// transform: scrolling or zooming every frame moves every view, so
    /// AppKit works out the cursor again each frame, which a customized
    /// pointer makes cost most of a pan.
    private(set) var drawn: (origin: CGPoint, zoom: CGFloat)?
    /// The canvas was drawn somewhere else (`drawn`): the views over it follow.
    var redrawn: (() -> Void)?
    /// A pan or a pinch starts: a glide under way gives way to it.
    var userMoves: (() -> Void)?
    private var panning = false
    private var pinching = false
    /// The scroll under way started with ⌘ down: it zooms.
    private var scrollZooming = false
    /// How much a point of ⌘-scroll zooms: finer than a pinch.
    static let scrollZoomStep: CGFloat = 0.003

    /// What's on screen of the canvas, as drawn.
    var shownRect: CGRect {
        let zoom = drawn?.zoom ?? magnification
        return CGRect(origin: drawn?.origin ?? contentView.bounds.origin,
                      size: CGSize(width: contentView.frame.width / zoom, height: contentView.frame.height / zoom))
    }

    var shownZoom: CGFloat { drawn?.zoom ?? magnification }

    /// Where a point on screen as scrolled is drawn instead, in the visible
    /// area (screen points, y down): scaled by `scale`, then moved by `offset`.
    var drawnMap: (scale: CGFloat, offset: CGPoint) {
        guard let drawn else { return (1, .zero) }
        let origin = contentView.bounds.origin
        return (drawn.zoom / magnification,
                CGPoint(x: (origin.x - drawn.origin.x) * drawn.zoom, y: (origin.y - drawn.origin.y) * drawn.zoom))
    }

    /// Draws the canvas as if scrolled to `view`; nil draws it where it is.
    func draw(at view: (origin: CGPoint, zoom: CGFloat)?) {
        drawn = view
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let layer = document.layer {
            // In the clip view's document points a point p is drawn at
            // scale * p + (origin - scale * drawn origin).
            let scale = shownZoom / magnification
            let origin = contentView.bounds.origin, to = shownRect.origin
            let move = CGPoint(x: origin.x - scale * to.x, y: origin.y - scale * to.y)
            layer.setAffineTransform(Self.transform(for: layer, scale: scale, move: move))
        }
        redrawn?()
        CATransaction.commit()
    }

    /// Scrolls to where the canvas is drawn, so it's drawn as it is again.
    func settleDrawn() {
        guard let view = drawn else { return }
        // One transaction: draw(at:)'s own would show the canvas undrawn,
        // where it was before the pan or pinch, for a frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        draw(at: nil)
        if magnification != view.zoom { magnification = view.zoom }
        contentView.scroll(to: view.origin)
        reflectScrolledClipView(contentView)
        CATransaction.commit()
    }

    /// The transform that draws `layer` mapped by `scale` then `move`, in
    /// its superlayer's coordinates, whatever its anchor point.
    static func transform(for layer: CALayer, scale: CGFloat, move: CGPoint) -> CGAffineTransform {
        let position = layer.position
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                 tx: (scale - 1) * position.x + move.x, ty: (scale - 1) * position.y + move.y)
    }

    /// A trackpad pan draws the canvas where it goes and scrolls once it
    /// stops (`drawn`).
    private func pans(_ event: NSEvent) -> Bool {
        guard event.hasPreciseScrollingDeltas, !(event.phase.isEmpty && event.momentumPhase.isEmpty) else { return false }
        if !panning {
            userMoves?()
            pinching = false
            settleDrawn()
            panning = true
        }
        lastPan = Date()
        let from = drawn?.origin ?? contentView.bounds.origin
        let origin = CGPoint(x: from.x - event.scrollingDeltaX / magnification, y: from.y - event.scrollingDeltaY / magnification)
        draw(at: (origin, magnification))
        let ends = event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
            || (event.momentumPhase.isEmpty && (event.phase.contains(.ended) || event.phase.contains(.cancelled)))
        if ends {
            panning = false
            settleDrawn()
        }
        return true
    }

    /// A pinch draws the canvas zoomed about the pointer and zooms once it
    /// stops (`drawn`), as a pan does.
    override func magnify(with event: NSEvent) {
        zoom(to: shownZoom * (1 + event.magnification), at: event)
        if event.phase.isEmpty || event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            pinching = false
            settleDrawn()
        }
    }

    /// ⌘ and a two-finger scroll zooms the same way, finer: fingers up zoom
    /// in. Its momentum is left out, so the zoom stops with your fingers.
    private func zooms(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let up = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let step = event.hasPreciseScrollingDeltas ? Self.scrollZoomStep : Self.scrollZoomStep * 10
        zoom(to: shownZoom * exp(up * step), at: event)
        if event.phase.isEmpty || event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            pinching = false
            settleDrawn()
        }
    }

    /// Draws the canvas at `zoom` about the pointer.
    private func zoom(to zoom: CGFloat, at event: NSEvent) {
        if !pinching {
            userMoves?()
            panning = false
            settleDrawn()
            pinching = true
        }
        let zoom = min(max(zoom, minMagnification), maxMagnification)
        // The document point under the pointer stays under it.
        let inView = convert(event.locationInWindow, from: nil)
        let pointer = CGPoint(x: inView.x, y: isFlipped ? inView.y : bounds.height - inView.y)
        let under = CGPoint(x: shownRect.minX + pointer.x / shownZoom, y: shownRect.minY + pointer.y / shownZoom)
        draw(at: (CGPoint(x: under.x - pointer.x / zoom, y: under.y - pointer.y / zoom), zoom))
    }
}

/// The canvas itself: the cards are its subviews, framed in document
/// points, y down. Draws nothing. Takes the keyboard when no card has it,
/// so keys go nowhere but ⌘A, which selects every card, Escape, which
/// deselects them, ⌘Z and ⇧⌘Z, which undo and redo, and the canvas's
/// one-letter shortcuts (`typed`). Dragging on it between the cards draws
/// a marquee.
final class CanvasDocumentView: NSView {
    /// A click between the cards (CanvasController.canvasClicked), with ⇧
    /// or not.
    var clicked: ((Bool) -> Void)?
    /// The marquee from the click to the pointer, as it's dragged.
    var dragged: ((CGRect) -> Void)?
    var dragEnded: (() -> Void)?
    var selectedAll: (() -> Void)?
    var deselected: (() -> Void)?
    /// A letter typed with no modifier: true when it was a shortcut.
    var typed: ((String) -> Bool)?
    /// Where the last click between the cards landed, in document points.
    private(set) var start: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Back to front: the zones, their labels, the cards in `stackIndex`
    /// order, so a card over a zone's label hides it. Reorders without
    /// taking views out of the window, so the focused pane keeps keyboard
    /// focus.
    func restack() {
        sortSubviews({ a, b, _ in
            func depth(_ view: NSView) -> Int {
                view is CanvasZoneLabelLayer ? Int.min + 1 : (view as? CanvasStacked)?.stackIndex ?? Int.min
            }
            let left = depth(a), right = depth(b)
            return left < right ? .orderedAscending : left > right ? .orderedDescending : .orderedSame
        }, context: nil)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        clicked?(event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragged?(CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                        width: abs(point.x - start.x), height: abs(point.y - start.y)))
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        dragEnded?()
    }

    override func selectAll(_ sender: Any?) {
        selectedAll?()
    }

    /// The Edit menu's Undo has no shortcut: a pane's ⌘Z is its own
    /// keybinding, so with no pane focused nothing else would take it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard window?.firstResponder === self, event.charactersIgnoringModifiers?.lowercased() == "z",
              mods == .command || mods == [.command, .shift], let undo = window?.undoManager else {
            return super.performKeyEquivalent(with: event)
        }
        if mods.contains(.shift) { undo.redo() } else { undo.undo() }
        return true
    }

    /// Pointer moves anywhere on the canvas, over the cards too, so the
    /// canvas can show a hand over a selected group (its event monitor
    /// sees them).
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
        }
    }

    override func mouseMoved(with event: NSEvent) {}

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return deselected?() ?? () }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods.isEmpty, !event.isARepeat, let key = event.charactersIgnoringModifiers?.lowercased(),
           typed?(key) == true { return }
        super.keyDown(with: event)
    }
}

/// The Lostty website's background: its paper color and dots, a square
/// 14pt grid, the same on screen at every zoom and moving as the canvas
/// pans. The dots are one picture, a gap bigger than the view each way;
/// panning only moves it (no drawing), and it's redrawn only when the gap
/// (the zoom), the view's size or the appearance changes.
final class CanvasGridView: NSView {
    weak var scrollView: CanvasScrollView?
    private let dots = CALayer()

    /// The website's `--paper` and `--dot` (website/custom.html).
    static let background = NSColor(name: "LosttyCanvasBackground") { appearance in
        isDark(appearance) ? hex(0x0E0B12) : hex(0xF3F2F6)
    }
    static let dot = NSColor(name: "LosttyCanvasDot") { appearance in
        isDark(appearance) ? hex(0x2A2432) : hex(0xCDC6D7)
    }
    /// The website's dot: solid to 1pt, fading out by 1.6pt.
    static let dotRadius: CGFloat = 1
    static let dotFade: CGFloat = 1.6

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// What the picture was drawn for.
    private var drawn: (size: CGSize, scale: CGFloat)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        dots.anchorPoint = .zero
        layer?.addSublayer(dots)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Self.background.cgColor
        drawn = nil
        update()
    }

    override func layout() {
        super.layout()
        update()
    }

    /// The canvas panned or zoomed: the picture only moves (the dots keep
    /// their spacing at every zoom), and is redrawn only for a new size,
    /// screen or appearance.
    func update() {
        guard let scrollView, bounds.width > 0, bounds.height > 0 else { return }
        let gap = CanvasGrid.spacing
        let scale = window?.backingScaleFactor ?? 2
        // A whole number of gaps, so the picture is the same either way up.
        let size = CGSize(width: ((bounds.width / gap.width).rounded(.up) + 2) * gap.width,
                          height: ((bounds.height / gap.height).rounded(.up) + 2) * gap.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if drawn?.size != size || drawn?.scale != scale {
            dots.contents = picture(gap: gap, size: size, scale: scale)
            dots.contentsScale = scale
            dots.bounds = CGRect(origin: .zero, size: size)
            drawn = (size, scale)
        }
        // Each dot sits mid-cell; one row and column of them start off-view.
        let first = CanvasGrid.firstDot(origin: scrollView.shownRect.origin, zoom: scrollView.shownZoom)
        let top = first.y - gap.height / 2 - gap.height
        dots.position = CGPoint(x: first.x - gap.width / 2 - gap.width,
                                y: layer?.isGeometryFlipped == true ? top : bounds.height - top - size.height)
        CATransaction.commit()
    }

    /// The dots: one drawn, then stamped at every gap.
    private func picture(gap: CGSize, size: CGSize, scale: CGFloat) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        var color = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = Self.dot.cgColor
        }
        let side = Self.dotFade * 2
        guard let stamp = CGContext(
            data: nil, width: Int((side * scale).rounded(.up)), height: Int((side * scale).rounded(.up)),
            bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info),
            let gradient = CGGradient(
                colorsSpace: space, colors: [color, color, color.copy(alpha: 0) ?? color] as CFArray,
                locations: [0, Self.dotRadius / Self.dotFade, 1])
        else { return nil }
        stamp.scaleBy(x: scale, y: scale)
        let middle = CGPoint(x: Self.dotFade, y: Self.dotFade)
        stamp.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle,
                                 endRadius: Self.dotFade, options: [])
        guard let dot = stamp.makeImage(), let context = CGContext(
            data: nil, width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up)),
            bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        var y = gap.height / 2
        while y < size.height {
            var x = gap.width / 2
            while x < size.width {
                context.draw(dot, in: CGRect(x: x - Self.dotFade, y: y - Self.dotFade, width: side, height: side))
                x += gap.width
            }
            y += gap.height
        }
        return context.makeImage()
    }
}

/// The grid with the scroll view over it, over that the selection's
/// outline, and over that the + button, the selection's bar, the dock, the
/// zoom meter and the notification stack, pinned to the window's edges at
/// every zoom.
final class CanvasSurfaceView: NSView {
    let scrollView = CanvasScrollView(frame: .zero)
    let selection = CanvasSelectionView()
    let selectionBar = CanvasSelectionBarView(rootView: CanvasSelectionBar())
    let addMenu = CanvasAddMenuView()
    let dockState = CanvasDockState()
    lazy var dock = CanvasDockView(state: dockState)
    let zones = CanvasZoneLayer(frame: NSRect(x: 0, y: 0, width: CanvasModel.size, height: CanvasModel.size))
    private let grid = CanvasGridView(frame: .zero)
    private let notifications = CanvasNotificationsView(rootView: NotificationStackView())
    private let zoomState = CanvasZoomMeterState()
    private lazy var zoomMeter = PassthroughHostingView(rootView: CanvasZoomMeter(state: zoomState))

    init() {
        super.init(frame: .zero)
        grid.scrollView = scrollView
        addSubview(grid)
        addSubview(scrollView)
        scrollView.document.addSubview(zones)
        scrollView.document.addSubview(zones.labels)
        selection.document = scrollView.document
        addSubview(selection)
        selectionBar.isHidden = true
        addSubview(selectionBar)
        addSubview(addMenu)
        addSubview(dock)
        zoomMeter.sizingOptions = [.intrinsicContentSize]
        zoomMeter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomMeter)
        // As big as its bubbles, at the top right.
        notifications.sizingOptions = [.intrinsicContentSize]
        notifications.translatesAutoresizingMaskIntoConstraints = false
        addSubview(notifications)
        NSLayoutConstraint.activate([
            notifications.topAnchor.constraint(equalTo: topAnchor),
            notifications.trailingAnchor.constraint(equalTo: trailingAnchor),
            zoomMeter.topAnchor.constraint(equalTo: topAnchor),
            zoomMeter.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        NotificationCenter.default.addObserver(
            self, selector: #selector(canvasMoved), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.redrawn = { [weak self] in self?.redrawn() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The canvas was drawn somewhere it isn't scrolled to, for the controller.
    var shownMoved: (() -> Void)?

    /// The selection's outline and bar follow the canvas as drawn
    /// (`CanvasScrollView.drawn`). The view is unflipped, the map y down;
    /// the bar moves but keeps its size, as it does at any zoom.
    private func redrawn() {
        let map = scrollView.drawnMap, height = bounds.height
        func shown(_ point: CGPoint) -> CGPoint {
            CGPoint(x: map.scale * point.x + map.offset.x, y: map.scale * point.y + height * (1 - map.scale) - map.offset.y)
        }
        if let layer = selection.layer {
            let origin = shown(.zero)
            layer.setAffineTransform(CanvasScrollView.transform(for: layer, scale: map.scale, move: origin))
        }
        let top = CGPoint(x: selectionBar.frame.midX, y: selectionBar.frame.maxY), moved = shown(top)
        selectionBar.layer?.setAffineTransform(CGAffineTransform(translationX: moved.x - top.x, y: moved.y - top.y))
        grid.update()
        zoomState.zoomed(to: scrollView.shownZoom)
        shownMoved?()
    }

    override func layout() {
        super.layout()
        grid.frame = bounds
        scrollView.frame = bounds
        selection.frame = bounds
        let picked = selection.selected.reduce(CGRect.null) { $0.union($1) }
        if !picked.isNull {
            selectionBar.frame = CanvasSelectionBarView.frame(
                size: selectionBar.fittingSize, under: convert(picked, from: scrollView.document), in: bounds)
        }
        dock.frame = CanvasDockView.frame(size: dock.fittingSize, in: bounds)
        // Its button `margin` in from the bottom right (the view is unflipped).
        let size = CanvasAddMenuView.size, room = CanvasAddMenuView.shadowRoom, margin = CanvasAddMenuView.margin
        addMenu.frame = NSRect(
            x: bounds.maxX - margin - size.width + room, y: bounds.minY + margin - room,
            width: size.width, height: size.height)
    }

    @objc private func canvasMoved() {
        zoomState.zoomed(to: scrollView.shownZoom)
        grid.update()
        selection.needsDisplay = true
        needsLayout = true
    }

    /// Whether a click at `point` (in the window) is on what floats over
    /// the cards: the + menu, the selection's bar, the dock, a
    /// notification, or a zone's label no card covers there.
    func floats(at point: NSPoint) -> Bool {
        addMenu.covers(point) || selectionBar.covers(point) || dock.covers(point)
            || notifications.hitTest(convert(point, from: nil)) != nil
            || scrollView.document.hitTest(scrollView.contentView.convert(point, from: nil))?
                .isDescendant(of: zones.labels) == true
    }
}

/// The canvas's one notification stack, for every card: with no bubbles up,
/// clicks go on to the cards under its corner.
final class CanvasNotificationsView: NSHostingView<NotificationStackView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        LosttyNotifications.shared.items.isEmpty ? nil : super.hitTest(point)
    }
}
#endif
