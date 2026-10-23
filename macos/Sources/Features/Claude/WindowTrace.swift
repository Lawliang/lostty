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
        /// the bottom edge, over their bottom glow.
        var subagents = false
        /// The bottom glow's colors: the skin trace's, as under a skin
        /// trace (with no skin, the trace's own, not the website's).
        var glow: RGB
        var glow2: RGB

        var colors: TraceColors { TraceColors(primary: primary, secondary: secondary) }
        var glowColors: TraceColors { TraceColors(primary: glow, secondary: glow2) }
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
            pane: pane, primary: primary, secondary: secondary, since: since, speed: trace.speed, subagents: subagents,
            glow: trace.color, glow2: trace.color2)
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

    /// How strongly the subagents' bottom glow shows under the Window
    /// Light: softer than under a skin trace.
    static let bottomGlowStrength = 0.5

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
    /// it's mirrored so the tail stays behind the head. `tail` shortens the
    /// tail toward the head, 1 its full length and 0 none.
    static func shades(_ colors: TraceColors, clockwise: Bool = true, tail length: Double = 1) -> [Shade] {
        let tail = colors.secondary, head = colors.primary, lit = tip(colors)
        let tints: [(RGB, Double)] = [(tail, 0), (tail, 0), (tail, 0.7), (head, 1), (lit, 1), (lit, 0), (lit, 0)]
        let locations = stopLocations.enumerated().map { i, location in
            (1...2).contains(i) ? stopLocations[3] - (stopLocations[3] - location) * length : location
        }
        let shades = zip(tints, locations).map { Shade(rgb: $0.0, alpha: $0.1, location: $1) }
        guard !clockwise else { return shades }
        return shades.reversed().map { Shade(rgb: $0.rgb, alpha: $0.alpha, location: 1 - $0.location) }
    }

    /// One frame of the light: where its gradient points (`endPoint`),
    /// which way it runs, how much of its tail shows, how strongly the
    /// subagents' bottom glow shows, and how much of the light shows off
    /// the bottom edge.
    struct Frame: Equatable {
        var endPoint: CGPoint
        var clockwise: Bool
        var tail: Double
        var bottom: Double
        var sides: Double
    }

    /// The light at `elapsed` in a pane whose inside edge is `rect`, moving
    /// `journey` there.
    static func frame(
        _ journey: TraceOverlay.Journey, lighting: Lighting, route: TraceRoute, in rect: CGRect, elapsed: Double
    ) -> Frame {
        let elapsed = max(0, elapsed)
        let course: TraceCourse = lighting.subagents ? .subagents : .route(route)
        let head = head(journey, since: lighting.since, in: rect, elapsed: elapsed, course: course, speed: lighting.speed)
        let turn = turn(toward: head.point, from: CGPoint(x: rect.midX, y: rect.midY), clockwise: head.clockwise)
        // Lit once the head reaches the bottom edge, as under a skin trace.
        let onBottom = journey.motion.bottomGlow(at: elapsed)
        let bottom = lighting.subagents ? TraceFrame.intensity(elapsed: elapsed) * onBottom * bottomGlowStrength : 0
        let legSeconds = TraceFrame.legSeconds(speed: lighting.speed)
        return Frame(
            endPoint: endPoint(turn: turn), clockwise: head.clockwise,
            tail: tail(journey.motion, course: course, elapsed: elapsed, legSeconds: legSeconds),
            bottom: bottom, sides: 1 - onBottom)
    }

    /// How much of its tail the light shows. Along the bottom for subagents
    /// the head turns back at each corner, where the gradient's tail would
    /// jump round behind it; so the tail shrinks into the head as it slows
    /// into the corner, and grows again as it leaves.
    static func tail(_ motion: TraceMotion, course: TraceCourse, elapsed: Double, legSeconds: Double) -> Double {
        let legs = motion.legs
        guard course == .subagents, let leg = legs.last, Set([leg.from, leg.to]) == [.bottomLeft, .bottomRight]
        else { return 1 }
        let u = min(1, max(0, (elapsed - leg.start) / legSeconds))
        let turnedBack = legs.count > 1 && legs[legs.count - 2].from == leg.to
        if u < 0.5, !turnedBack { return 1 }
        return min(1, 2 * sin(.pi * u))
    }

    /// The light's frames every `step` seconds over `duration` from
    /// `elapsed`, as `frame` finds them one at a time; worked out ahead on
    /// a copy of the journey, for Core Animation to play.
    static func frames(
        _ journey: TraceOverlay.Journey, lighting: Lighting, route: TraceRoute, in rect: CGRect,
        from elapsed: Double, duration: Double, step: Double
    ) -> [Frame] {
        let ahead = TraceOverlay.Journey()
        ahead.since = journey.since
        ahead.motion = journey.motion
        let count = Int((duration / step).rounded()) + 1
        return (0..<count).map {
            frame(ahead, lighting: lighting, route: route, in: rect, elapsed: elapsed + Double($0) * step)
        }
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
/// spills outside the box; a pane can't draw there); while only subagents
/// work, kept to the bottom edge over their bottom glow. Core Animation
/// plays the motion: every
/// few seconds it's handed the frames ahead (`WindowTrace.frames`), and
/// between those Lostty does nothing. Holds still while its window is
/// covered or minimized, and while the light fades out.
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
    /// Holds the glow and the line; its mask shows them only along the
    /// bottom edge while the head keeps to it for subagents.
    private let lightBox = CALayer()
    private let curtain = CALayer()
    private let edgeStrip = CALayer()
    private let sideCurtain = CALayer()
    /// How far in from the bottom edge the light shows then.
    private static let edgeStripDepth: CGFloat = 28
    /// Reduce Motion: no circling; the whole edge breathes.
    private let calm = CAShapeLayer()
    /// The subagents' bottom glow (TraceOverlay.drawBottomGlow) as an
    /// image; a frame only sets how strongly it shows.
    private let bottom = CALayer()
    private var bottomDrawn: BottomGlow?
    /// The glow mask as drawn: its size, and the zoom's line scale as y.
    private var maskDrawn: CGRect?
    /// Hands Core Animation the next frames before the last run out.
    private var handOn: Timer?
    private var occlusion: NSObjectProtocol?
    /// How far ahead Core Animation is given the motion, how often it's
    /// handed on, and how far apart the frames are (it blends between).
    private static let ahead: TimeInterval = 10
    private static let handOnEvery: TimeInterval = 8
    private static let step: TimeInterval = 1.0 / 30

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
        for part in [edgeStrip, sideCurtain] {
            part.backgroundColor = CGColor(gray: 0, alpha: 1)
            curtain.addSublayer(part)
        }
        lightBox.mask = curtain
        lightBox.addSublayer(glowBox)
        lightBox.addSublayer(lineBox)
        calm.fillColor = nil
        calm.isHidden = true
        bottom.contentsGravity = .resize
        bottom.opacity = 0
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
        if setup.zoom != old.zoom { needsLayout = true }
        // New colors draw now; a new size or zoom waits for layout's pause.
        if setup.lighting?.glow != old.lighting?.glow || setup.lighting?.glow2 != old.lighting?.glow2
            || setup.lighting?.subagents != old.lighting?.subagents {
            drawBottomGlow()
        }
        play()
        // After play, whose hold would put back the moving light's glow.
        if setup.reduceMotion != old.reduceMotion || setup.lighting?.primary != old.lighting?.primary
            || setup.lighting?.subagents != old.lighting?.subagents || setup.running != old.running {
            breathe()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if let layer, glowBox.superlayer !== layer {
            for sublayer in [lightBox, calm, bottom] { layer.addSublayer(sublayer) }
        }
        let scale = CanvasZoomCompensation.scale(zoom: setup.zoom)
        let side = max(bounds.width, bounds.height)
        let square = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        // The line is 2 points wide inside the edge, as SwiftUI's strokeBorder.
        let edge = CGPath(rect: bounds.insetBy(dx: scale, dy: scale), transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for box in [lightBox, curtain, glowBox, lineBox, calm, glowMask, lineMask, bottom] { box.frame = bounds }
        // The view is flipped: the bottom edge is at maxY.
        let depth = min(bounds.height, Self.edgeStripDepth * scale)
        edgeStrip.frame = CGRect(x: 0, y: bounds.height - depth, width: bounds.width, height: depth)
        sideCurtain.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - depth)
        glow.frame = square
        line.frame = square
        lineMask.path = edge
        lineMask.lineWidth = 2 * scale
        calm.path = edge
        calm.lineWidth = 2 * scale
        CATransaction.commit()
        if glowMask.contents == nil {
            drawImages()
        } else {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(drawImages), object: nil)
            perform(#selector(drawImages), with: nil, afterDelay: 0.15)
        }
        play()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        maskDrawn = nil
        bottomDrawn = nil
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
                MainActor.assumeIsolated { self?.play() }
            }
        }
        play()
    }

    /// The images, drawn once for a size: while the size keeps changing (a
    /// resize, a pinch), the last ones stretch and this waits for a pause.
    @objc private func drawImages() {
        drawGlowMask()
        drawBottomGlow()
    }

    /// The glow's band: a 12-point line along the edge blurred by 9.
    private func drawGlowMask() {
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

    /// What the bottom glow image shows.
    private struct BottomGlow: Equatable {
        var size: CGSize
        var scale: CGFloat
        var glow: RGB
        var glow2: RGB
    }

    /// The subagents' bottom glow at full strength, drawn as the skin
    /// traces draw it, at the size it's drawn at on a zoomed-out canvas.
    private func drawBottomGlow() {
        guard let lighting = setup.lighting, lighting.subagents, bounds.width > 0, bounds.height > 0 else { return }
        let scale = CanvasZoomCompensation.scale(zoom: setup.zoom)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let key = BottomGlow(size: size, scale: scale, glow: lighting.glow, glow2: lighting.glow2)
        guard key != bottomDrawn else { return }
        let colors = lighting.glowColors
        let renderer = ImageRenderer(content: Canvas { ctx, size in
            ctx.blendMode = .plusLighter
            TraceOverlay.drawBottomGlow(in: &ctx, rect: TraceOverlay.edgeRect(size), level: 1, colors: colors)
        }.frame(width: size.width, height: size.height))
        renderer.scale = (window?.backingScaleFactor ?? 2) * scale
        guard let image = renderer.cgImage else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bottom.contents = image
        CATransaction.commit()
        bottomDrawn = key
    }

    /// Hands Core Animation the light's next frames while it's lit,
    /// moving and on screen, and again every few seconds; otherwise holds
    /// it where it is.
    private func play() {
        let visible = window?.occlusionState.contains(.visible) == true
        guard let lighting = setup.lighting, setup.running, !setup.reduceMotion, visible, bounds.width > 0 else {
            hold()
            return
        }
        // Moved in the size it's drawn at on a zoomed-out canvas.
        let scale = CanvasZoomCompensation.scale(zoom: setup.zoom)
        let rect = TraceOverlay.edgeRect(CGSize(width: bounds.width / scale, height: bounds.height / scale))
        let elapsed = Date().timeIntervalSince(lighting.since)
        // The journey goes on to now; the frames ahead come from a copy.
        let now = WindowTrace.frame(journey, lighting: lighting, route: setup.route, in: rect, elapsed: elapsed)
        let frames = WindowTrace.frames(
            journey, lighting: lighting, route: setup.route, in: rect, from: elapsed, duration: Self.ahead,
            step: Self.step)
        let colors = lighting.colors
        func shown(_ frame: WindowTrace.Frame) -> Colors {
            Colors(WindowTrace.shades(colors, clockwise: frame.clockwise, tail: frame.tail))
        }
        let shades = frames.map(shown)
        let times = frames.indices.map { NSNumber(value: Double($0) / Double(frames.count - 1)) }
        func animation(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = times
            animation.duration = Self.ahead
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            let rate = Float(1 / TraceTiming.frameInterval)
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: rate / 2, maximum: rate, preferred: rate)
            return animation
        }
        let turn = animation("endPoint", frames.map { NSValue(point: $0.endPoint) })
        // A turn back flips the colors between two frames.
        let flips = animation("colors", shades.map(\.colors))
        let locations = animation("locations", shades.map(\.locations))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for gradient in [glow, line] {
            let current = shown(now)
            gradient.endPoint = now.endPoint
            gradient.colors = current.colors
            gradient.locations = current.locations
            gradient.add(turn, forKey: "turn")
            gradient.add(flips, forKey: "colors")
            gradient.add(locations, forKey: "locations")
        }
        bottom.opacity = Float(now.bottom)
        bottom.add(animation("opacity", frames.map { NSNumber(value: $0.bottom) }), forKey: "bottom")
        sideCurtain.opacity = Float(now.sides)
        sideCurtain.add(animation("opacity", frames.map { NSNumber(value: $0.sides) }), forKey: "sides")
        CATransaction.commit()
        guard handOn == nil else { return }
        handOn = Timer.scheduledTimer(withTimeInterval: Self.handOnEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.play() }
        }
    }

    /// Stops handing on and keeps the light as it shows now.
    private func hold() {
        handOn?.invalidate()
        handOn = nil
        guard glow.animation(forKey: "turn") != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for gradient in [glow, line] {
            if let shown = gradient.presentation() {
                gradient.endPoint = shown.endPoint
                gradient.colors = shown.colors
                gradient.locations = shown.locations
            }
            for key in ["turn", "colors", "locations"] { gradient.removeAnimation(forKey: key) }
        }
        if let shown = bottom.presentation() { bottom.opacity = shown.opacity }
        bottom.removeAnimation(forKey: "bottom")
        if let shown = sideCurtain.presentation() { sideCurtain.opacity = shown.opacity }
        sideCurtain.removeAnimation(forKey: "sides")
        CATransaction.commit()
    }

    /// A way round of the gradient's colors, as Core Animation takes them.
    private struct Colors {
        let colors: [CGColor]
        let locations: [NSNumber]

        init(_ shades: [WindowTrace.Shade]) {
            colors = shades.map(\.cgColor)
            locations = shades.map { NSNumber(value: $0.location) }
        }
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
        // Still, the bottom glow is simply on while only subagents work.
        if setup.reduceMotion {
            bottom.opacity = setup.lighting?.subagents == true ? Float(WindowTrace.bottomGlowStrength) : 0
        }
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
}

#endif
