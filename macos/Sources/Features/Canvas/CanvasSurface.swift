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

/// The faint dot grid behind the canvas, moving with it as it pans and
/// zooms. The dots are one picture, a gap bigger than the view each way;
/// panning only moves it (no drawing), and it's redrawn only when the gap
/// (the zoom), the view's size or the appearance changes.
final class CanvasGridView: NSView {
    weak var scrollView: NSScrollView?
    private let dots = CALayer()
    /// What the picture was drawn for.
    private var drawn: (gap: CGFloat, size: CGSize, scale: CGFloat)?

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
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        drawn = nil
        update()
    }

    override func layout() {
        super.layout()
        update()
    }

    /// The canvas panned or zoomed.
    func update() {
        guard let scrollView, bounds.width > 0, bounds.height > 0 else { return }
        let zoom = scrollView.magnification
        let gap = CanvasGrid.gap(zoom: zoom)
        let scale = window?.backingScaleFactor ?? 2
        // A whole number of gaps, so the picture is the same either way up.
        let size = CGSize(width: ((bounds.width / gap).rounded(.up) + 2) * gap,
                          height: ((bounds.height / gap).rounded(.up) + 2) * gap)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if drawn?.gap != gap || drawn?.size != size || drawn?.scale != scale {
            dots.contents = picture(gap: gap, size: size, scale: scale)
            dots.contentsScale = scale
            dots.bounds = CGRect(origin: .zero, size: size)
            drawn = (gap, size, scale)
        }
        // Each dot sits mid-cell; one row and column of them start off-view.
        let first = CanvasGrid.firstDot(origin: scrollView.contentView.bounds.origin, zoom: zoom)
        let top = first.y - gap / 2 - gap
        dots.position = CGPoint(x: first.x - gap / 2 - gap,
                                y: layer?.isGeometryFlipped == true ? top : bounds.height - top - size.height)
        CATransaction.commit()
    }

    private func picture(gap: CGFloat, size: CGSize, scale: CGFloat) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        var color = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.tertiaryLabelColor.withAlphaComponent(0.35).cgColor
        }
        context.setFillColor(color)
        let dot: CGFloat = 1.5
        var rects: [CGRect] = []
        var y = gap / 2
        while y < size.height {
            var x = gap / 2
            while x < size.width {
                rects.append(CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                x += gap
            }
            y += gap
        }
        context.fill(rects)
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

/// The canvas inside the window's SwiftUI layout (the icon row and usage
/// bar below it). SwiftUI never re-evaluates for a pan or zoom.
struct CanvasSurface: NSViewRepresentable {
    let view: CanvasSurfaceView

    func makeNSView(context: Context) -> CanvasSurfaceView { view }
    func updateNSView(_ nsView: CanvasSurfaceView, context: Context) {}
}
#endif
