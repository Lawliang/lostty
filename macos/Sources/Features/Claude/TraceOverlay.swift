#if os(macOS)
import AppKit
import SwiftUI

/// The Claude trace for one pane (spec §4). Lives in SurfaceWrapper's
/// ZStack; draws nothing while the pane is idle. On a zoomed-out canvas it
/// keeps its size on screen.
struct ClaudeTraceLayer: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @AppStorage(TraceStyle.defaultsKey, store: .ghostty) private var style = TraceStyle.initial
    /// The canvas's zoom on a card, 1 in a window.
    @State private var zoom: CGFloat = 1
    /// The head's motion, kept across frames: the Window Light's and its
    /// bottom glow's together, so the glow comes on as the light reaches
    /// the bottom edge.
    @State private var journey = TraceOverlay.Journey()

    var body: some View {
        let phase = runtime.phase(surfaceID)
        // In Window Light the website's light circles the pane while Claude
        // works; while only subagents or shells do, it runs along the
        // bottom edge over their bottom glow.
        let windowLight = style == .window
        ZStack {
            if windowLight {
                PaneLightView(surfaceID: surfaceID, journey: journey).modifier(CanvasZoomCompensation(zoom: zoom))
            }
            if !phase.isOff, !windowLight || phase.subagentsOnly,
               let trace = ResolvedTrace.resolve(skin: skins.effectiveSkin(surfaceID), enabled: skins.config.trace) {
                TraceOverlay(phase: phase, trace: trace, journey: journey, bottomOnly: windowLight,
                             headGlow: style != .skinNoGlow, canvasZoom: zoom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanvasZoomProbe(zoom: $zoom))
        .allowsHitTesting(false)
    }
}

/// On a zoomed-out canvas, draws its content as big on screen as at 100%:
/// laid out smaller by the zoom and scaled back up to fill, so the Window
/// Light's line and glow keep their width instead of thinning to nothing.
/// Zoomed in, and in a window, it draws as is.
struct CanvasZoomCompensation: ViewModifier {
    let zoom: CGFloat

    /// How much bigger than at 100% the content draws at `zoom`.
    static func scale(zoom: CGFloat) -> CGFloat {
        guard zoom > 0 else { return 1 }
        return 1 / min(1, zoom)
    }

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let scale = Self.scale(zoom: zoom)
            content
                .frame(width: geo.size.width / scale, height: geo.size.height / scale)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct TraceOverlay: View {
    static let inset: CGFloat = 1.5

    let phase: TracePhase
    let trace: ResolvedTrace
    let journey: Journey
    /// Only the subagents' bottom glow, without the racing head.
    var bottomOnly = false
    /// The glowing circle round the racing head.
    var headGlow = true
    /// The canvas's zoom on a card, 1 in a window.
    var canvasZoom: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TraceRoute.defaultsKey, store: .ghostty) private var route = TraceRoute.initial
    @State private var windowVisible = true

    /// The head's motion, kept across frames. A class so drawing can
    /// advance it without invalidating the view.
    final class Journey {
        var since: Date?
        var motion = TraceMotion()
    }

    private var drawing: TraceDrawing {
        TraceDrawing(phase: phase, trace: trace, route: route, bottomOnly: bottomOnly, headGlow: headGlow,
                     reduceMotion: reduceMotion)
    }

    var body: some View {
        if canvasZoom < 1 {
            ZoomedTraceView(drawing: drawing, journey: journey, zoom: canvasZoom)
        } else {
            TimelineView(.animation(paused: !windowVisible)) { timeline in
                Canvas { ctx, size in
                    drawing.draw(in: &ctx, size: size, at: timeline.date, journey: journey)
                }
            }
            .background(OcclusionProbe(visible: $windowVisible))
        }
    }

    /// The pane's inside edge. Degenerate panes collapse to a point so every
    /// position stays finite.
    static func edgeRect(_ size: CGSize) -> CGRect {
        let width = max(0, size.width - 2 * inset)
        let height = max(0, size.height - 2 * inset)
        guard width > 0, height > 0 else { return CGRect(x: inset, y: inset, width: 0, height: 0) }
        return CGRect(x: inset, y: inset, width: width, height: height)
    }

    /// While only subagents work: light rising into the pane from the bottom
    /// edge, under the trace. A soft band in the trace's colors, brightest
    /// at the edge, with a blurred line along the edge itself.
    static func drawBottomGlow(in ctx: inout GraphicsContext, rect: CGRect, level: Double, colors: TraceColors) {
        guard level > 0, rect.width > 0 else { return }
        let depth = min(56, rect.height * 0.3)
        let band = CGRect(x: rect.minX, y: rect.maxY - depth, width: rect.width, height: depth + inset)
        let rise = Gradient(stops: [
            .init(color: colors.tail.opacity(0), location: 0),
            .init(color: colors.tail.opacity(0.12 * level), location: 0.55),
            .init(color: colors.head.opacity(0.32 * level), location: 1),
        ])
        ctx.fill(Path(band), with: .linearGradient(
            rise, startPoint: CGPoint(x: rect.midX, y: band.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

        var edge = Path()
        edge.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        edge.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        var bloom = ctx
        bloom.addFilter(.blur(radius: 8))
        bloom.stroke(edge, with: .color(colors.head.opacity(0.5 * level)), lineWidth: 10)
    }

    /// Reduce Motion: no racing; the course's edge breathes with a 2s period.
    static func drawCalmGlow(
        in ctx: inout GraphicsContext, outline: Path, intensity: Double, time: Double, colors: TraceColors
    ) {
        let breath = 0.25 + 0.35 * (0.5 + 0.5 * sin(2 * .pi * time / 2))
        ctx.stroke(outline, with: .color(colors.head.opacity(breath * intensity)), lineWidth: 2)
    }
}

/// One pane's trace, frame by frame: what TraceOverlay's Canvas draws, and
/// on a zoomed-out canvas ZoomedTraceView.
struct TraceDrawing {
    let phase: TracePhase
    let trace: ResolvedTrace
    let route: TraceRoute
    let bottomOnly: Bool
    let headGlow: Bool
    let reduceMotion: Bool

    /// The frame at `date` in a pane of `size`.
    func draw(in ctx: inout GraphicsContext, size: CGSize, at date: Date, journey: TraceOverlay.Journey) {
        guard case .racing(let since, let subagents) = phase else { return }
        let rect = TraceOverlay.edgeRect(size)
        let course: TraceCourse = subagents ? .subagents : .route(route)
        let elapsed = max(0, date.timeIntervalSince(since))
        let colors = TraceColors(trace)
        let time = date.timeIntervalSinceReferenceDate
        ctx.blendMode = .plusLighter
        if bottomOnly {
            // Under the Window Light, which moves the head: lit once it
            // reaches the bottom edge, as under a skin trace.
            var level = TraceFrame.intensity(elapsed: elapsed)
            if !reduceMotion {
                journey.motion.advance(to: elapsed, course: course, legSeconds: TraceFrame.legSeconds(speed: trace.speed))
                level *= journey.motion.bottomGlow(at: elapsed)
            }
            TraceOverlay.drawBottomGlow(in: &ctx, rect: rect, level: level, colors: colors)
            return
        }
        if reduceMotion {
            let intensity = TraceFrame.intensity(elapsed: elapsed)
            if subagents { TraceOverlay.drawBottomGlow(in: &ctx, rect: rect, level: intensity, colors: colors) }
            TraceOverlay.drawCalmGlow(in: &ctx, outline: course.outline(in: rect), intensity: intensity, time: time, colors: colors)
            return
        }

        if journey.since != since {
            journey.since = since
            journey.motion = TraceMotion()
        }
        let legSeconds = TraceFrame.legSeconds(speed: trace.speed)
        journey.motion.advance(to: elapsed, course: course, legSeconds: legSeconds)
        let path = journey.motion.path(in: rect, at: elapsed, legSeconds: legSeconds)
        guard path.length > 0 else { return }
        // The tail is sized by the person's route, so it keeps its
        // length on the bottom edge; early on it is only as long as
        // the way travelled.
        let tail = min(path.length, trace.length * TraceCourse.route(route).lapLength(in: rect))
        let frame = TraceFrame(
            head: 1, length: tail / path.length, intensity: TraceFrame.intensity(elapsed: elapsed), headGlow: headGlow)
        TraceOverlay.drawBottomGlow(in: &ctx, rect: rect, level: journey.motion.bottomGlow(at: elapsed) * frame.intensity,
                                    colors: colors)
        TraceRenderers.renderer(for: trace.style)
            .draw(in: &ctx, along: path, frame: frame, time: time, colors: colors)
    }
}

/// The trace on a zoomed-out canvas. There SwiftUI's Canvas paints only
/// part of the pane, a share the zoom sets from its top-left corner, so
/// AppKit draws the same frames instead, and the canvas scales them as it
/// does any view. Drawn at the pane's size on screen, so lines and glows
/// keep their width.
struct ZoomedTraceView: NSViewRepresentable {
    let drawing: TraceDrawing
    let journey: TraceOverlay.Journey
    let zoom: CGFloat

    func makeNSView(context: Context) -> DrawingView { DrawingView() }

    func updateNSView(_ view: DrawingView, context: Context) {
        view.drawing = drawing
        view.journey = journey
        view.zoom = zoom
    }

    final class DrawingView: NSView {
        var drawing: TraceDrawing?
        var zoom: CGFloat = 1
        var journey = TraceOverlay.Journey()
        private var timer: Timer?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layerContentsRedrawPolicy = .onSetNeedsDisplay
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override var isFlipped: Bool { true }

        /// Clicks go to the pane under it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            timer?.invalidate()
            timer = nil
            guard window != nil else { return }
            // A frame each display refresh, as TimelineView(.animation),
            // pinches and scrolls included.
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        deinit { timer?.invalidate() }

        /// Paused while the window is minimized or covered.
        private func tick() {
            guard window?.occlusionState.contains(.visible) == true else { return }
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let drawing, zoom > 0, let cg = NSGraphicsContext.current?.cgContext else { return }
            let journey = self.journey
            let date = Date()
            let size = CGSize(width: bounds.width * zoom, height: bounds.height * zoom)
            let renderer = ImageRenderer(content: Canvas { ctx, size in
                drawing.draw(in: &ctx, size: size, at: date, journey: journey)
            }.frame(width: size.width, height: size.height))
            let height = bounds.height
            let zoom = zoom
            renderer.render { _, render in
                cg.saveGState()
                // The renderer draws y-up, at the pane's size on screen.
                cg.translateBy(x: 0, y: height)
                cg.scaleBy(x: 1 / zoom, y: -1 / zoom)
                render(cg)
                cg.restoreGState()
            }
        }
    }
}

/// Reports the zoom of the canvas the view is on (1 off the canvas), as
/// it changes.
struct CanvasZoomProbe: NSViewRepresentable {
    @Binding var zoom: CGFloat

    func makeNSView(context: Context) -> Probe {
        Probe { magnification in
            DispatchQueue.main.async { if zoom != magnification { zoom = magnification } }
        }
    }

    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        private let onChange: (CGFloat) -> Void
        private var token: NSObjectProtocol?
        /// The zoom last reported: panning posts the same notification.
        private var reported: CGFloat?

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        /// Clicks go to the pane under it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            var view = superview
            while let next = view, !(next is CanvasScrollView) { view = next.superview }
            guard let canvas = view as? CanvasScrollView else { return report(1) }
            // The clip view's bounds change as the canvas pans and zooms.
            token = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: canvas.contentView, queue: .main
            ) { [weak self, weak canvas] _ in
                if let canvas { self?.report(canvas.magnification) }
            }
            report(canvas.magnification)
        }

        private func report(_ zoom: CGFloat) {
            guard zoom != reported else { return }
            reported = zoom
            onChange(zoom)
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}

/// Reports whether the hosting window is visible (not minimized or fully
/// covered), so the animation can pause.
struct OcclusionProbe: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> Probe {
        Probe { isVisible in
            DispatchQueue.main.async { if visible != isVisible { visible = isVisible } }
        }
    }

    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        private let onChange: (Bool) -> Void
        private var token: NSObjectProtocol?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                guard let window = self?.window else { return }
                self?.onChange(window.occlusionState.contains(.visible))
            }
            onChange(window.occlusionState.contains(.visible))
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
#endif
