#if os(macOS)
import AppKit
import QuartzCore

/// Where the canvas looks: the document point in the middle of the view, and
/// the zoom.
struct CanvasView: Equatable {
    var center: CGPoint
    var zoom: CGFloat
}

extension CanvasZoom {
    /// How long a glide to a card takes.
    static let glideDuration: CFTimeInterval = 0.45

    /// A glide's progress at `time` (0…1 of its duration): fast off the
    /// mark, then easing gently into place (ease-out cubic).
    static func eased(_ time: Double) -> Double {
        let time = min(max(time, 0), 1)
        return 1 - pow(1 - time, 3)
    }

    /// The view `progress` (eased, 0…1) of the way from `from` to `to`. The
    /// zoom changes at an even rate (each step scales by the same factor),
    /// and the view scales about the one document point that stays put on
    /// screen the whole way, so the card grows into place instead of
    /// sliding sideways while it grows. With no zoom change it's a plain pan.
    static func view(from: CanvasView, to: CanvasView, progress: Double) -> CanvasView {
        let progress = CGFloat(progress)
        let zoom = from.zoom * pow(to.zoom / from.zoom, progress)
        // How much of the way the view has scaled (from.zoom / zoom goes
        // from 1 to `last`): the center moves the same share of the way.
        let last = from.zoom / to.zoom
        let share = abs(last - 1) < 0.001 ? progress : (from.zoom / zoom - 1) / (last - 1)
        let center = CGPoint(
            x: from.center.x + (to.center.x - from.center.x) * share,
            y: from.center.y + (to.center.y - from.center.y) * share)
        return CanvasView(center: center, zoom: zoom)
    }
}

/// A glide under way: where it set out from and is going, and the frame
/// clock that steps it.
@MainActor
final class CanvasGlide: NSObject {
    let from: CanvasView
    let to: CanvasView
    private let start = CACurrentMediaTime()
    private let step: @MainActor (CanvasGlide) -> Void
    private var clock: AnyObject?
    /// The view the last step showed, to tell when a pinch or scroll took over.
    var shown: CanvasView?

    init(from: CanvasView, to: CanvasView, on view: NSView, step: @escaping @MainActor (CanvasGlide) -> Void) {
        self.from = from
        self.to = to
        self.step = step
        super.init()
        if #available(macOS 14, *) {
            let link = view.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            clock = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 120, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        }
    }

    /// How far along it is in time, 0…1.
    var time: Double {
        min(1, (CACurrentMediaTime() - start) / CanvasZoom.glideDuration)
    }

    @objc private func tick() { step(self) }

    func stop() {
        if #available(macOS 14, *), let link = clock as? CADisplayLink { link.invalidate() }
        (clock as? Timer)?.invalidate()
        clock = nil
    }
}

extension CanvasController {
    /// What the view shows now.
    var currentView: CanvasView {
        let visible = scrollView.documentVisibleRect
        return CanvasView(center: CGPoint(x: visible.midX, y: visible.midY), zoom: scrollView.magnification)
    }

    /// Glides the view to `target`: zoom and pan together, eased. Jumps
    /// there when the system asks for reduced motion.
    func glide(to target: CanvasView) {
        stopGlide()
        let target = CanvasView(center: target.center, zoom: CanvasZoom.clamped(target.zoom))
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window?.isVisible == true else {
            show(target)
            settleZoom()
            return
        }
        glide = CanvasGlide(from: currentView, to: target, on: scrollView) { [weak self] glide in
            self?.glideStep(glide)
        }
    }

    /// A pinch or scroll takes over from a glide.
    func stopGlide() {
        glide?.stop()
        glide = nil
    }

    private func glideStep(_ glide: CanvasGlide) {
        // Something else moved the view since the last step: it's theirs now.
        if let shown = glide.shown, !Self.same(currentView, shown) {
            stopGlide()
            scheduleSettle()
            return
        }
        let time = glide.time
        show(CanvasZoom.view(from: glide.from, to: glide.to, progress: CanvasZoom.eased(time)))
        glide.shown = currentView
        guard time >= 1 else { return }
        stopGlide()
        settleZoom()
    }

    private func show(_ view: CanvasView) {
        scrollView.magnification = view.zoom
        center(on: view.center)
    }

    private static func same(_ a: CanvasView, _ b: CanvasView) -> Bool {
        abs(a.zoom - b.zoom) < 0.0001 && abs(a.center.x - b.center.x) < 0.5 && abs(a.center.y - b.center.y) < 0.5
    }
}
#endif
