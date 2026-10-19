#if os(macOS)
import AppKit
import SwiftUI

/// The canvas's scroll view: two-finger scrolling over empty canvas pans
/// it, in any direction (not locked to the swipe's main axis), pinching
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
}

/// The canvas itself: the cards are its subviews, framed in document
/// points, y down. Draws nothing.
final class CanvasDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// The Lostty website's background: its paper color and dot grid, the
/// dots moving with the canvas as it pans and zooms. The dots are one picture, a gap bigger than the view each way;
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
    private var drawn: (gap: CGSize, size: CGSize, scale: CGFloat)?
    private var redrawWork: DispatchWorkItem?

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

    /// The canvas panned or zoomed. Panning only moves the picture; while
    /// the zoom changes the picture is stretched to the new spacing and
    /// redrawn once it rests (redrawing each step cost more than a frame).
    func update() {
        guard let scrollView, bounds.width > 0, bounds.height > 0 else { return }
        let zoom = scrollView.magnification
        let gap = CanvasGrid.gap(zoom: zoom)
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let drawn, drawn.scale == scale, covers(drawn, gap: gap) {
            if drawn.gap != gap { redrawSoon() }
        } else {
            redraw(gap: gap, scale: scale)
        }
        guard let drawn else { CATransaction.commit(); return }
        let stretch = gap.width / drawn.gap.width
        dots.setAffineTransform(CGAffineTransform(scaleX: stretch, y: stretch))
        // Each dot sits mid-cell; one row and column of them start off-view.
        let first = CanvasGrid.firstDot(origin: scrollView.contentView.bounds.origin, zoom: zoom)
        let top = first.y - gap.height / 2 - gap.height
        dots.position = CGPoint(x: first.x - gap.width / 2 - gap.width,
                                y: layer?.isGeometryFlipped == true ? top : bounds.height - top - drawn.size.height * stretch)
        CATransaction.commit()
    }

    /// Whether the picture, stretched to `gap`, still covers the view.
    private func covers(_ drawn: (gap: CGSize, size: CGSize, scale: CGFloat), gap: CGSize) -> Bool {
        let stretch = gap.width / drawn.gap.width
        guard stretch > 0.5, stretch < 2 else { return false }
        return drawn.size.width * stretch >= bounds.width + 2 * gap.width
            && drawn.size.height * stretch >= bounds.height + 2 * gap.height
    }

    private func redrawSoon() {
        redrawWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.drawn = nil
            self?.update()
        }
        redrawWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CanvasZoom.settle, execute: work)
    }

    /// Half as big again as the view (a whole number of gaps, so the
    /// picture is the same either way up), so zooming out has room to
    /// stretch before it must redraw.
    private func redraw(gap: CGSize, scale: CGFloat) {
        redrawWork?.cancel()
        let size = CGSize(width: ((bounds.width * 1.5 / gap.width).rounded(.up) + 2) * gap.width,
                          height: ((bounds.height * 1.5 / gap.height).rounded(.up) + 2) * gap.height)
        dots.contents = picture(gap: gap, size: size, scale: scale)
        dots.contentsScale = scale
        dots.bounds = CGRect(origin: .zero, size: size)
        drawn = (gap, size, scale)
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

/// The grid with the scroll view over it.
final class CanvasSurfaceView: NSView {
    let scrollView = CanvasScrollView(frame: .zero)
    private let grid = CanvasGridView(frame: .zero)

    init() {
        super.init(frame: .zero)
        grid.scrollView = scrollView
        addSubview(grid)
        addSubview(scrollView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(canvasMoved), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        grid.frame = bounds
        scrollView.frame = bounds
    }

    @objc private func canvasMoved() {
        grid.update()
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
