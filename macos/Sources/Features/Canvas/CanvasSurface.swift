#if os(macOS)
import AppKit
import SwiftUI

/// The canvas's scroll view: two-finger scrolling pans it, over a card too
/// (but scrolls the focused pane over it; ⌥ swaps the two over a pane), in
/// any direction (not locked to the swipe's main axis), pinching
/// zooms it 25%–200% (its clip view scales, so clicks still land on the
/// right cell), and it has no scrollers.
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
    /// The ticket whose text the scroll under way scrolls (TicketDetailsHost),
    /// or nil. Decided where the scroll starts, as `scrollingPane` is; the
    /// canvas never hands a scroll on to it.
    weak var scrollingTicket: NSView?

    /// A scroll gesture's first event, or a mouse wheel's click.
    static func startsScroll(_ event: NSEvent) -> Bool {
        event.phase.contains(.began) || (event.phase.isEmpty && event.momentumPhase.isEmpty)
    }

    override func scrollWheel(with event: NSEvent) {
        if Self.startsScroll(event) {
            // Started over the canvas, or a pane or ticket handed it on: it pans.
            scrollingPane = nil
            scrollingTicket = nil
        } else if let pane = scrollingPane {
            pane.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }
}

/// The canvas itself: the cards are its subviews, framed in document
/// points, y down. Draws nothing. Takes the keyboard when no card has it,
/// so keys go nowhere.
final class CanvasDocumentView: NSView {
    /// A click between the cards (CanvasController.canvasClicked).
    var clicked: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        clicked?()
    }
}

/// The Lostty website's background: its paper color and dots, four times
/// as dense, the same on screen at every zoom and moving as the canvas
/// pans. The dots are one picture, a gap bigger than the view each way;
/// panning only moves it (no drawing), and it's redrawn only when the gap
/// (the zoom), the view's size or the appearance changes.
final class CanvasGridView: NSView {
    weak var scrollView: NSScrollView?
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
        let first = CanvasGrid.firstDot(origin: scrollView.contentView.bounds.origin, zoom: scrollView.magnification)
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

/// The grid with the scroll view over it, and over that the + button and
/// the notification stack, pinned to the window's corners at every zoom.
final class CanvasSurfaceView: NSView {
    let scrollView = CanvasScrollView(frame: .zero)
    let addMenu = CanvasAddMenuView()
    private let grid = CanvasGridView(frame: .zero)
    private let notifications = CanvasNotificationsView(rootView: NotificationStackView())

    init() {
        super.init(frame: .zero)
        grid.scrollView = scrollView
        addSubview(grid)
        addSubview(scrollView)
        addSubview(addMenu)
        // As big as its bubbles, at the top right.
        notifications.sizingOptions = [.intrinsicContentSize]
        notifications.translatesAutoresizingMaskIntoConstraints = false
        addSubview(notifications)
        NSLayoutConstraint.activate([
            notifications.topAnchor.constraint(equalTo: topAnchor),
            notifications.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        NotificationCenter.default.addObserver(
            self, selector: #selector(canvasMoved), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        grid.frame = bounds
        scrollView.frame = bounds
        // Its button `margin` in from the bottom right (the view is unflipped).
        let size = CanvasAddMenuView.size, room = CanvasAddMenuView.shadowRoom, margin = CanvasAddMenuView.margin
        addMenu.frame = NSRect(
            x: bounds.maxX - margin - size.width + room, y: bounds.minY + margin - room,
            width: size.width, height: size.height)
    }

    @objc private func canvasMoved() {
        grid.update()
    }
}

/// The canvas's one notification stack, for every card: with no bubbles up,
/// clicks go on to the cards under its corner.
final class CanvasNotificationsView: NSHostingView<NotificationStackView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        LosttyNotifications.shared.items.isEmpty ? nil : super.hitTest(point)
    }
}

/// The canvas as the window's SwiftUI content. SwiftUI never re-evaluates
/// for a pan or zoom.
struct CanvasSurface: NSViewRepresentable {
    let view: CanvasSurfaceView

    func makeNSView(context: Context) -> CanvasSurfaceView { view }
    func updateNSView(_ nsView: CanvasSurfaceView, context: Context) {}
}
#endif
