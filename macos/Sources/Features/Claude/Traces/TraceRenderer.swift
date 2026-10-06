#if os(macOS)
import SwiftUI

/// Draws one trace style for one frame. Implementations are stateless:
/// everything comes from the frame, the time and the colors.
protocol TraceRenderer {
    /// `time` is seconds since the reference date, for flicker and particles.
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors)
}

enum TraceRenderers {
    static func renderer(for style: BuiltinTrace) -> any TraceRenderer {
        switch style {
        case .beam: BeamTrace()
        case .comet: CometTrace()
        case .sunset: SunsetTrace()
        case .datastream: DatastreamTrace()
        case .sonar: SonarTrace()
        case .ember: EmberTrace()
        case .bubbles: BubblesTrace()
        case .bolt: BoltTrace()
        case .tide: TideTrace()
        case .blade: BladeTrace()
        case .petal: PetalTrace()
        case .arrow: ArrowTrace()
        case .tempest: TempestTrace()
        }
    }
}

/// Shared drawing helpers for trace styles.
enum TraceDraw {
    /// Brightness along the tail: 0 at the tail end, 1 at the head, with most
    /// of the light packed near the head like a motion streak.
    static func falloff(_ t: Double) -> Double {
        pow(min(1, max(0, t)), 2.4)
    }

    /// Head brightness flicker, about 0.8–1.0, so the flash feels alive.
    static func flicker(_ time: Double) -> Double {
        0.88 + 0.07 * sin(time * 47) + 0.05 * sin(time * 113)
    }

    /// The shared light streak: a wide soft bloom, a glow, a white-hot core
    /// that cools into the skin color down the tail, sparkles rippling back
    /// along the tail, and a flaring head. `scale` sizes every layer.
    static func light(
        _ ctx: inout GraphicsContext, _ path: EdgePath, frame: TraceFrame, time: Double,
        colors: TraceColors, scale: CGFloat = 1, sparkles: Bool = true
    ) {
        var bloom = ctx
        bloom.addFilter(.blur(radius: 9 * scale))
        tail(&bloom, path, frame: frame, width: { 18 * scale * CGFloat(0.35 + 0.65 * falloff($0)) },
             color: { colors.blend($0).opacity(0.55 * falloff($0)) })

        var glow = ctx
        glow.addFilter(.blur(radius: 3 * scale))
        tail(&glow, path, frame: frame, width: { 7 * scale * CGFloat(0.3 + 0.7 * falloff($0)) },
             color: { colors.blend($0).opacity(0.9 * falloff($0)) })

        tail(&ctx, path, frame: frame, width: { max(0.6, 3.2 * scale * CGFloat(falloff($0))) },
             color: { colors.hot($0) .opacity(falloff($0)) })

        if sparkles { self.sparkles(&ctx, path, frame: frame, time: time, colors: colors, scale: scale) }
        flare(&ctx, path.sample(at: frame.head), time: time, colors: colors, intensity: frame.intensity, scale: scale)
    }

    /// Strokes the tail behind the head as `pieces` short segments. `t` runs
    /// 0 at the tail end to 1 at the head; `color` carries its own opacity.
    static func tail(
        _ ctx: inout GraphicsContext, _ path: EdgePath, frame: TraceFrame, pieces: Int = 24,
        width: (Double) -> CGFloat, color: (Double) -> Color
    ) {
        let start = frame.head - frame.length
        for i in 0..<pieces {
            let t0 = Double(i) / Double(pieces)
            let t1 = Double(i + 1) / Double(pieces)
            let seg = path.segment(from: start + frame.length * t0, to: start + frame.length * t1)
            ctx.stroke(
                seg, with: .color(color(t1).opacity(frame.intensity)),
                style: StrokeStyle(lineWidth: width(t1), lineCap: .round))
        }
    }

    /// Bright glints that run backward along the tail and fade as they go.
    static func sparkles(
        _ ctx: inout GraphicsContext, _ path: EdgePath, frame: TraceFrame, time: Double,
        colors: TraceColors, scale: CGFloat = 1, count: Int = 7
    ) {
        for k in 0..<count {
            let back = (Double(k) / Double(count) + time * 2.2).truncatingRemainder(dividingBy: 1)
            let fade = 1 - back
            let p = path.offsetPoint(at: frame.head - frame.length * back,
                                     inward: CGFloat(TraceDraw.noise(k, 9) - 0.5) * 3 * scale)
            glow(&ctx, at: p, radius: 4 * scale, color: colors.head, opacity: 0.7 * fade * frame.intensity)
            dot(&ctx, at: p, radius: 1.2 * scale * CGFloat(fade), color: .white, opacity: fade * frame.intensity)
        }
    }

    /// The head: a bloom, a streak stretched along the direction of travel,
    /// a cross glint, and a white-hot point, all flickering.
    static func flare(
        _ ctx: inout GraphicsContext, _ head: EdgePath.Sample, time: Double, colors: TraceColors,
        intensity: Double, scale: CGFloat = 1
    ) {
        let f = flicker(time) * intensity
        let p = head.point
        glow(&ctx, at: p, radius: 24 * scale, color: colors.head, opacity: 0.55 * f)
        glow(&ctx, at: p, radius: 10 * scale, color: colors.head, opacity: 0.9 * f)

        // Streak: long behind the head, short ahead, white at the center.
        let back = 34 * scale, ahead = 10 * scale
        let from = CGPoint(x: p.x - head.tangent.dx * back, y: p.y - head.tangent.dy * back)
        let to = CGPoint(x: p.x + head.tangent.dx * ahead, y: p.y + head.tangent.dy * ahead)
        var streak = Path()
        streak.move(to: from)
        streak.addLine(to: to)
        let gradient = Gradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(0.95 * f), location: back / (back + ahead)),
            .init(color: .white.opacity(0), location: 1),
        ])
        ctx.stroke(streak, with: .linearGradient(gradient, startPoint: from, endPoint: to),
                   style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))

        // Cross glint across the edge, pulsing.
        let reach = (7 + 5 * CGFloat(sin(time * 31) * 0.5 + 0.5)) * scale
        var glint = Path()
        glint.move(to: CGPoint(x: p.x - head.normal.dx * reach, y: p.y - head.normal.dy * reach))
        glint.addLine(to: CGPoint(x: p.x + head.normal.dx * reach, y: p.y + head.normal.dy * reach))
        ctx.stroke(glint, with: .color(.white.opacity(0.6 * f)), style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round))

        dot(&ctx, at: p, radius: 3.6 * scale, color: .white, opacity: f)
    }

    /// A soft blurred disc, for heads and sparks.
    static func glow(_ ctx: inout GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        var layer = ctx
        layer.addFilter(.blur(radius: radius / 2))
        layer.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                   with: .color(color.opacity(opacity)))
    }

    /// A crisp filled circle.
    static func dot(_ ctx: inout GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                 with: .color(color.opacity(opacity)))
    }

    /// Deterministic pseudo-random value in 0..<1 for particle `i`, `seed`.
    static func noise(_ i: Int, _ seed: Int) -> Double {
        var x = UInt64(bitPattern: Int64(i &* 73_856_093 ^ seed &* 19_349_663))
        x ^= x >> 33
        x &*= 0xff51afd7ed558ccd
        x ^= x >> 33
        x &*= 0xc4ceb9fe1a85ec53
        x ^= x >> 33
        return Double(x >> 11) / Double(1 << 53)
    }
}
#endif
