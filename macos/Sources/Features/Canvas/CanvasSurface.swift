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
/// zooms: one cheap fill per frame.
final class CanvasGridView: NSView {
    weak var scrollView: NSScrollView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard let scrollView, let context = NSGraphicsContext.current?.cgContext else { return }
        let zoom = scrollView.magnification
        let gap = CanvasGrid.gap(zoom: zoom)
        let first = CanvasGrid.firstDot(origin: scrollView.contentView.bounds.origin, zoom: zoom)
        let dot: CGFloat = 1.5
        var rects: [CGRect] = []
        var y = first.y
        while y < bounds.height {
            var x = first.x
            while x < bounds.width {
                rects.append(CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                x += gap
            }
            y += gap
        }
        context.setFillColor(NSColor.tertiaryLabelColor.withAlphaComponent(0.35).cgColor)
        context.fill(rects)
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
        grid.needsDisplay = true
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
