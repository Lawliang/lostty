#if os(macOS)
import AppKit
import SwiftUI

/// The website's trace (website/custom.html, "Claude's trace"): a light
/// circling each pane's edge while Claude works in it, in that pane's
/// colors. Shown instead of the skin traces when Lostty → Claude Trace
/// Style is Window Light. While only subagents or background shells work,
/// it runs back and forth along the bottom edge, as the skin traces do.
enum WindowTrace {
    /// Showing and going, as the website's opacity transition.
    static let fadeSeconds: Double = 0.5

    /// The website's pink and cyan (`--mk-a1`, `--mk-a2`), for panes with no skin.
    static let websitePink = RGB(hex: "#ff3df2")!
    static let websiteCyan = RGB(hex: "#28e7ff")!

    /// A lit pane's colors.
    struct Lighting: Equatable {
        var pane: UUID
        /// The head's color (the skin's trace color) and the tail's.
        var primary: RGB
        var secondary: RGB
        /// When Claude started working, and the skin trace's speed: the
        /// light runs as that pane's skin trace would.
        var since: Date
        var speed: Double
        /// Only subagents or background shells work: the light keeps to
        /// the bottom edge.
        var subagents = false

        var colors: TraceColors { TraceColors(primary: primary, secondary: secondary) }
    }

    /// A pane is lit while Claude, its subagents or its background shells
    /// work in it, in its skin's trace colors, or the website's with no
    /// skin. Not when its trace is off (`trace = "none"`, `[defaults]
    /// trace = false`).
    static func lighting(pane: UUID, phase: TracePhase, skin: Skin?, enabled: Bool) -> Lighting? {
        guard case .racing(let since, let subagents) = phase,
              let trace = ResolvedTrace.resolve(skin: skin, enabled: enabled) else { return nil }
        let primary = skin == nil ? websitePink : trace.color
        let secondary = skin == nil ? websiteCyan : trace.color2
        return Lighting(
            pane: pane, primary: primary, secondary: secondary, since: since, speed: trace.speed, subagents: subagents)
    }

    /// Where the light's head is on the pane's inside edge `rect`, and
    /// whether it's running clockwise: moved by the skin traces' own motion
    /// (corner to corner along the course, a leg's time set by the speed,
    /// easing into and out of each corner), so the two styles run alike.
    static func head(
        _ journey: TraceOverlay.Journey, since: Date, in rect: CGRect, elapsed: Double, course: TraceCourse, speed: Double
    ) -> (point: CGPoint, clockwise: Bool) {
        if journey.since != since {
            journey.since = since
            journey.motion = TraceMotion()
        }
        let legSeconds = TraceFrame.legSeconds(speed: speed)
        let elapsed = max(0, elapsed)
        journey.motion.advance(to: elapsed, course: course, legSeconds: legSeconds)
        guard let leg = journey.motion.legs.last,
              let end = journey.motion.path(in: rect, at: elapsed, legSeconds: legSeconds).runs.last?.to
        else { return (CGPoint(x: rect.midX, y: rect.minY), true) }
        return (end, leg.to == leg.from.clockwiseNext)
    }

    /// The gradient's turn, in degrees clockwise, that puts its tip on
    /// `head` as seen from `center`, with the tail behind it.
    static func turn(toward head: CGPoint, from center: CGPoint, clockwise: Bool) -> Double {
        let bearing = atan2(head.y - center.y, head.x - center.x) * 180 / .pi
        // The gradient starts at the top (-90°); its tip is a share of the way round.
        let tip = clockwise ? stopLocations[4] : 1 - stopLocations[4]
        let turn = (Double(bearing) + 90 - tip * 360).truncatingRemainder(dividingBy: 360)
        return turn < 0 ? turn + 360 : turn
    }

    /// Where the website's conic gradient changes, as shares of a turn
    /// from its start: dark, the tail coming in, the head, its tip, and
    /// dark again just past it.
    static let stopLocations: [Double] = [0, 0.64, 0.80, 0.93, 0.95, 0.96, 1]

    /// How far the tip is lightened toward white: a little brighter than
    /// the head, still its color.
    static let tipLightening = 0.35

    /// The tip's color.
    static func tip(_ colors: TraceColors) -> RGB {
        colors.primary.mixed(with: .white, amount: tipLightening)
    }

    /// One color of the gradient: an sRGB color at an opacity, at a share
    /// of the turn.
    struct Shade: Equatable {
        var rgb: RGB
        var alpha: Double
        var location: Double

        var cgColor: CGColor {
            CGColor(srgbRed: CGFloat(rgb.r) / 255, green: CGFloat(rgb.g) / 255, blue: CGFloat(rgb.b) / 255,
                    alpha: CGFloat(alpha))
        }
    }

    /// The website's gradient, `transparent 0 64%, color-mix(accent2 70%)
    /// 80%, accent 93%, #fff 95%, transparent 96%`, but with the tip the
    /// head's color lightened rather than white. Running counterclockwise,
    /// it's mirrored so the tail stays behind the head.
    static func shades(_ colors: TraceColors, clockwise: Bool = true) -> [Shade] {
        let tail = colors.secondary, head = colors.primary, lit = tip(colors)
        let tints: [(RGB, Double)] = [(tail, 0), (tail, 0), (tail, 0.7), (head, 1), (lit, 1), (lit, 0), (lit, 0)]
        let shades = zip(tints, stopLocations).map { Shade(rgb: $0.0, alpha: $0.1, location: $1) }
        guard !clockwise else { return shades }
        return shades.reversed().map { Shade(rgb: $0.rgb, alpha: $0.alpha, location: 1 - $0.location) }
    }

    /// Where a conic gradient's `endPoint` goes, in its square layer's unit
    /// space, for the gradient turned `turn` degrees clockwise from
    /// starting at the top. In a flipped view a conic gradient starts
    /// toward `endPoint` and sweeps clockwise, as SwiftUI's
    /// AngularGradient does; it measures angles in unit space, so the
    /// layer must be square.
    static func endPoint(turn: Double) -> CGPoint {
        let start = (turn - 90) * .pi / 180
        return CGPoint(x: 0.5 + 0.5 * cos(start), y: 0.5 + 0.5 * sin(start))
    }
}

/// The light round one pane. Draws nothing until Claude works there.
/// Core Animation draws it (WindowLightView): a frame only turns two
/// gradients, where a SwiftUI timeline had the whole window laid out.
struct PaneLightView: View {
    let surfaceID: UUID
    let phase: TracePhase
    /// The head's motion, shared with the bottom glow (ClaudeTraceLayer).
    let journey: TraceOverlay.Journey
    /// The canvas's zoom on a card, 1 in a window.
    var zoom: CGFloat = 1
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TraceRoute.defaultsKey, store: .ghostty) private var route = TraceRoute.initial
    /// The last lighting, kept while the light fades out.
    @State private var shown: WindowTrace.Lighting?
    @State private var lit = false

    private var lighting: WindowTrace.Lighting? {
        WindowTrace.lighting(
            pane: surfaceID, phase: phase,
            skin: skins.effectiveSkin(surfaceID), enabled: skins.config.trace)
    }

    var body: some View {
        WindowLightLayer(
            setup: WindowLightView.Setup(
                lighting: shown, running: lit, route: route, reduceMotion: reduceMotion, zoom: zoom),
            journey: journey)
            .opacity(lit ? 1 : 0)
            .animation(.easeInOut(duration: WindowTrace.fadeSeconds), value: lit)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { light(lighting) }
            .onChange(of: lighting) { light($0) }
    }

    private func light(_ lighting: WindowTrace.Lighting?) {
        if let lighting { shown = lighting }
        lit = lighting != nil
    }
}

private struct WindowLightLayer: NSViewRepresentable {
    let setup: WindowLightView.Setup
    let journey: TraceOverlay.Journey

    func makeNSView(context: Context) -> WindowLightView { WindowLightView() }

    func updateNSView(_ view: WindowLightView, context: Context) {
        view.update(setup, journey: journey)
    }
}

/// The Window Light in Core Animation layers: the website's conic gradient
/// turned round the pane's center, seen through a thin line along the
/// edge and, softer, a blurred band just inside it (the website's glow
/// spills outside the box; a pane can't draw there). Each display frame
/// it points the gradients at the head (`WindowTrace.head`) and nothing
/// else redraws; the GPU does the rest. Stops while its window is covered
/// or minimized, and while the light fades out.
final class WindowLightView: NSView {
    struct Setup: Equatable {
        var lighting: WindowTrace.Lighting?
        /// Lit and moving; off, it holds its last frame while it fades.
        var running = false
        var route = TraceRoute.initial
        var reduceMotion = false
        var zoom: CGFloat = 1
    }

    private var setup = Setup()
    private var journey = TraceOverlay.Journey()
    /// Each gradient is a square (conic gradients measure angles in unit
    /// space) inside a pane-sized box that its mask cuts.
    private let glowBox = CALayer()
    private let glow = CAGradientLayer()
    private let glowMask = CALayer()
    private let lineBox = CALayer()
    private let line = CAGradientLayer()
    private let lineMask = CAShapeLayer()
    /// Reduce Motion: no circling; the whole edge breathes.
    private let calm = CAShapeLayer()
    /// Which way the gradient's colors run now; nil to set them afresh.
    private var clockwise: Bool?
    /// The glow mask as drawn: its size, and the zoom's line scale as y.
    private var maskDrawn: CGRect?
    private var clock: AnyObject?
    private var occlusion: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        for gradient in [glow, line] {
            gradient.type = .conic
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        }
        glowBox.opacity = 0.55
        glowBox.mask = glowMask
        glowBox.addSublayer(glow)
        // While a resize or a pinch goes on, the old mask stretches.
        glowMask.contentsGravity = .resize
        lineMask.fillColor = nil
        lineMask.strokeColor = CGColor(gray: 0, alpha: 1)
        lineBox.mask = lineMask
        lineBox.addSublayer(line)
        calm.fillColor = nil
        calm.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// Clicks go to the pane under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ setup: Setup, journey: TraceOverlay.Journey) {
        self.journey = journey
        guard setup != self.setup else { return }
        let old = self.setup
        self.setup = setup
        if setup.lighting != old.lighting { clockwise = nil }
        if setup.zoom != old.zoom { needsLayout = true }
        if setup.reduceMotion != old.reduceMotion || setup.lighting?.primary != old.lighting?.primary
            || setup.running != old.running {
            breathe()
        }
        turn()
        updateClock()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if let layer, glowBox.superlayer !== layer {
            for sublayer in [glowBox, lineBox, calm] { layer.addSublayer(sublayer) }
        }
        let scale = CanvasZoomCompensation.scale(zoom: setup.zoom)
        let side = max(bounds.width, bounds.height)
        let square = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        // The line is 2 points wide inside the edge, as SwiftUI's strokeBorder.
        let edge = CGPath(rect: bounds.insetBy(dx: scale, dy: scale), transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for box in [glowBox, lineBox, calm, glowMask, lineMask] { box.frame = bounds }
        glow.frame = square
        line.frame = square
        lineMask.path = edge
        lineMask.lineWidth = 2 * scale
        calm.path = edge
        calm.lineWidth = 2 * scale
        CATransaction.commit()
        if glowMask.contents == nil {
            drawGlowMask()
        } else {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(drawGlowMask), object: nil)
            perform(#selector(drawGlowMask), with: nil, afterDelay: 0.15)
        }
        turn()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        maskDrawn = nil
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
        if let window {
            occlusion = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateClock() }
            }
        }
        updateClock()
    }

    /// The glow's band: a 12-point line along the edge blurred by 9, as an
    /// image. Drawn once for a size; while the size keeps changing (a
    /// resize, a pinch), the last one stretches and this waits for a pause.
    @objc private func drawGlowMask() {
        let scale = CanvasZoomCompensation.scale(zoom: setup.zoom)
        let key = CGRect(x: 0, y: scale, width: bounds.width, height: bounds.height)
        guard key != maskDrawn, bounds.width > 0, bounds.height > 0 else { return }
        let renderer = ImageRenderer(content: Rectangle()
            .strokeBorder(lineWidth: 12 * scale)
            .blur(radius: 9 * scale)
            .frame(width: bounds.width, height: bounds.height))
        renderer.scale = window?.backingScaleFactor ?? 2
        guard let image = renderer.cgImage else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowMask.contents = image
        CATransaction.commit()
        maskDrawn = key
    }

    /// Points the gradients at the head, as it is now.
    private func turn() {
        guard let lighting = setup.lighting, !setup.reduceMotion, bounds.width > 0 else { return }
        // Moved in the size it's drawn at on a zoomed-out canvas.
        let scale = CanvasZoomCompensation.scale(zoom: setup.zoom)
        let rect = TraceOverlay.edgeRect(CGSize(width: bounds.width / scale, height: bounds.height / scale))
        let head = WindowTrace.head(
            journey, since: lighting.since, in: rect, elapsed: Date().timeIntervalSince(lighting.since),
            course: lighting.subagents ? .subagents : .route(setup.route), speed: lighting.speed)
        let turn = WindowTrace.turn(toward: head.point, from: CGPoint(x: rect.midX, y: rect.midY),
                                    clockwise: head.clockwise)
        let end = WindowTrace.endPoint(turn: turn)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if clockwise != head.clockwise {
            clockwise = head.clockwise
            let shades = WindowTrace.shades(lighting.colors, clockwise: head.clockwise)
            for gradient in [glow, line] {
                gradient.colors = shades.map(\.cgColor)
                gradient.locations = shades.map { NSNumber(value: $0.location) }
            }
        }
        glow.endPoint = end
        line.endPoint = end
        CATransaction.commit()
    }

    /// Reduce Motion: the edge in the head's color, breathing with a 2 s
    /// period, which Core Animation plays by itself.
    private func breathe() {
        let calmNow = setup.reduceMotion && setup.lighting != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowBox.isHidden = calmNow
        lineBox.isHidden = calmNow
        calm.isHidden = !calmNow
        calm.removeAnimation(forKey: "breath")
        if calmNow, let lighting = setup.lighting {
            calm.strokeColor = WindowTrace.Shade(rgb: lighting.primary, alpha: 1, location: 0).cgColor
            calm.opacity = 0.25
            if setup.running {
                let breath = CABasicAnimation(keyPath: "opacity")
                breath.fromValue = 0.25
                breath.toValue = 0.6
                breath.duration = 1
                breath.autoreverses = true
                breath.repeatCount = .infinity
                breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                calm.add(breath, forKey: "breath")
            }
        }
        CATransaction.commit()
    }

    /// A frame each display refresh while lit, moving and on screen.
    private func updateClock() {
        let visible = window?.occlusionState.contains(.visible) == true
        let wanted = setup.running && setup.lighting != nil && !setup.reduceMotion && visible
        if wanted, clock == nil {
            if #available(macOS 14, *) {
                let link = displayLink(target: self, selector: #selector(tick))
                let rate = Float(1 / TraceTiming.frameInterval)
                link.preferredFrameRateRange = CAFrameRateRange(minimum: rate / 2, maximum: rate, preferred: rate)
                link.add(to: .main, forMode: .common)
                clock = link
            } else {
                let timer = Timer(timeInterval: TraceTiming.frameInterval, target: self, selector: #selector(tick),
                                  userInfo: nil, repeats: true)
                RunLoop.main.add(timer, forMode: .common)
                clock = timer
            }
        } else if !wanted, let clock {
            if #available(macOS 14, *), let link = clock as? CADisplayLink { link.invalidate() }
            (clock as? Timer)?.invalidate()
            self.clock = nil
        }
    }

    @objc private func tick() { turn() }
}

#endif
