#if os(macOS)
import AppKit
import SwiftUI

/// The website's trace (website/custom.html, "Claude's trace"): a light
/// circling each pane's edge while Claude works in it, in that pane's
/// colors. Shown instead of the skin traces when Lostty → Claude Trace
/// Style is Window Light. A pane where only subagents work keeps its
/// bottom glow.
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

        var colors: TraceColors { TraceColors(primary: primary, secondary: secondary) }
    }

    /// A pane is lit while Claude itself works in it (not only its
    /// subagents), in its skin's trace colors, or the website's with no
    /// skin. Not when its trace is off (`trace = "none"`, `[defaults]
    /// trace = false`).
    static func lighting(pane: UUID, phase: TracePhase, skin: Skin?, enabled: Bool) -> Lighting? {
        guard case .racing(let since, false) = phase,
              let trace = ResolvedTrace.resolve(skin: skin, enabled: enabled) else { return nil }
        let primary = skin == nil ? websitePink : trace.color
        let secondary = skin == nil ? websiteCyan : trace.color2
        return Lighting(pane: pane, primary: primary, secondary: secondary, since: since, speed: trace.speed)
    }

    /// Where the light's head is on the pane's inside edge `rect`, and
    /// whether it's running clockwise: moved by the skin traces' own motion
    /// (corner to corner along the person's route, a leg's time set by the
    /// speed, easing into and out of each corner), so the two styles run
    /// alike.
    static func head(
        _ journey: TraceOverlay.Journey, since: Date, in rect: CGRect, elapsed: Double, route: TraceRoute, speed: Double
    ) -> (point: CGPoint, clockwise: Bool) {
        if journey.since != since {
            journey.since = since
            journey.motion = TraceMotion()
        }
        let legSeconds = TraceFrame.legSeconds(speed: speed)
        let elapsed = max(0, elapsed)
        journey.motion.advance(to: elapsed, course: .route(route), legSeconds: legSeconds)
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

    /// The website's gradient, `transparent 0 64%, color-mix(accent2 70%)
    /// 80%, accent 93%, #fff 95%, transparent 96%`, but with the tip in
    /// the head's color rather than white. Running counterclockwise, it's
    /// mirrored so the tail stays behind the head.
    static func stops(_ colors: TraceColors, clockwise: Bool = true) -> [Gradient.Stop] {
        let shades: [Color] = [
            colors.tail.opacity(0), colors.tail.opacity(0), colors.tail.opacity(0.7), colors.head,
            colors.head, colors.head.opacity(0), colors.head.opacity(0),
        ]
        let stops = zip(shades, stopLocations).map { Gradient.Stop(color: $0, location: $1) }
        guard !clockwise else { return stops }
        return stops.reversed().map { Gradient.Stop(color: $0.color, location: 1 - $0.location) }
    }
}

/// The light round one pane. Draws nothing until Claude works there.
struct PaneLightView: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TraceRoute.defaultsKey, store: .ghostty) private var route = TraceRoute.initial
    @State private var windowVisible = true
    /// The last lighting, kept while the light fades out.
    @State private var shown: WindowTrace.Lighting?
    @State private var lit = false
    @State private var journey = TraceOverlay.Journey()

    private var lighting: WindowTrace.Lighting? {
        WindowTrace.lighting(
            pane: surfaceID, phase: runtime.phase(surfaceID),
            skin: skins.effectiveSkin(surfaceID), enabled: skins.config.trace)
    }

    var body: some View {
        GeometryReader { geo in
            if let shown {
                TimelineView(.animation(paused: !lit || !windowVisible)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(shown.since)
                    if reduceMotion {
                        calm(size: geo.size, colors: shown.colors, elapsed: elapsed)
                    } else {
                        let rect = TraceOverlay.edgeRect(geo.size)
                        let head = WindowTrace.head(journey, since: shown.since, in: rect, elapsed: elapsed,
                                                    route: route, speed: shown.speed)
                        WindowTraceRing(
                            colors: shown.colors,
                            angle: WindowTrace.turn(toward: head.point, from: CGPoint(x: rect.midX, y: rect.midY),
                                                    clockwise: head.clockwise),
                            clockwise: head.clockwise, cornerRadius: 0, size: geo.size)
                    }
                }
            }
        }
        .opacity(lit ? 1 : 0)
        .animation(.easeInOut(duration: WindowTrace.fadeSeconds), value: lit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background(OcclusionProbe(visible: $windowVisible))
        .onAppear { light(lighting) }
        .onChange(of: lighting) { light($0) }
    }

    private func light(_ lighting: WindowTrace.Lighting?) {
        if let lighting { shown = lighting }
        lit = lighting != nil
    }

    /// Reduce Motion: no circling; the whole edge breathes with a 2s period.
    private func calm(size: CGSize, colors: TraceColors, elapsed: Double) -> some View {
        let breath = 0.25 + 0.35 * (0.5 + 0.5 * sin(2 * .pi * elapsed / 2))
        return Rectangle().strokeBorder(colors.head, lineWidth: 2)
            .opacity(breath)
            .frame(width: size.width, height: size.height)
    }
}

/// One frame of the light: the website's conic gradient turned `angle`
/// round the pane's center, seen through a thin line along the edge and,
/// softer, a glow just inside it (the website's glow spills outside the
/// box; a pane can't draw there).
struct WindowTraceRing: View {
    let colors: TraceColors
    let angle: Double
    var clockwise = true
    let cornerRadius: CGFloat
    let size: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let side = (size.width * size.width + size.height * size.height).squareRoot()
        let sweep = AngularGradient(
            gradient: Gradient(stops: WindowTrace.stops(colors, clockwise: clockwise)), center: .center,
            startAngle: .degrees(-90), endAngle: .degrees(270))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(angle))
            .frame(width: size.width, height: size.height)
        ZStack {
            sweep
                .mask(shape.strokeBorder(lineWidth: 12).blur(radius: 9))
                .opacity(0.55)
            sweep
                .mask(shape.strokeBorder(lineWidth: 2))
        }
        .frame(width: size.width, height: size.height)
    }
}

#endif
