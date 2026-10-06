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
        case .bolt: BoltTrace()
        // The other styles arrive in the next task; until then they draw a beam.
        default: BeamTrace()
        }
    }
}

/// Shared drawing helpers for trace styles.
enum TraceDraw {
    /// Strokes the tail behind the head as `pieces` short segments. `t` runs
    /// 0 at the tail end to 1 at the head; opacity ramps with it.
    static func tail(
        _ ctx: inout GraphicsContext, _ path: EdgePath, frame: TraceFrame, pieces: Int = 28,
        width: (Double) -> CGFloat, color: (Double) -> Color
    ) {
        let start = frame.head - frame.length
        for i in 0..<pieces {
            let t0 = Double(i) / Double(pieces)
            let t1 = Double(i + 1) / Double(pieces)
            let seg = path.segment(from: start + frame.length * t0, to: start + frame.length * t1)
            ctx.stroke(
                seg, with: .color(color(t1).opacity(frame.intensity * t1)),
                style: StrokeStyle(lineWidth: width(t1), lineCap: .round))
        }
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
