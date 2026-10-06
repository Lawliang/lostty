#if os(macOS)
import SwiftUI

/// thunderhead: forked lightning that re-strikes every 50ms.
struct BoltTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let strike = Int(time / 0.05)
        let pieces = 18
        let start = frame.head - frame.length
        var bolt = Path()
        var forks = Path()
        for i in 0...pieces {
            let t = Double(i) / Double(pieces)
            // Jagged inward offsets, calmer near the head so it stays on the edge.
            let jitter = i == pieces ? 0 : CGFloat(TraceDraw.noise(i, strike)) * 18 * CGFloat(1 - t * 0.7)
            let p = path.offsetPoint(at: start + frame.length * t, inward: jitter)
            if i == 0 { bolt.move(to: p) } else { bolt.addLine(to: p) }
            if i == pieces / 3 || i == 2 * pieces / 3 {
                forks.move(to: p)
                let reach = jitter + 16 + CGFloat(TraceDraw.noise(i, strike + 1)) * 18
                forks.addLine(to: path.offsetPoint(at: start + frame.length * (t - 0.07), inward: reach))
            }
        }
        let flicker = frame.intensity * (0.65 + 0.35 * TraceDraw.noise(0, strike))
        var halo = ctx
        halo.addFilter(.blur(radius: 10))
        halo.stroke(bolt, with: .color(colors.tail.opacity(0.7 * flicker)), lineWidth: 16)
        var glow = ctx
        glow.addFilter(.blur(radius: 2.5))
        glow.stroke(bolt, with: .color(colors.head.opacity(flicker)), lineWidth: 6)
        ctx.stroke(bolt, with: .color(Color.white.opacity(0.95 * flicker)), style: StrokeStyle(lineWidth: 2.2, lineJoin: .bevel))
        glow.stroke(forks, with: .color(colors.head.opacity(0.8 * flicker)), lineWidth: 4)
        ctx.stroke(forks, with: .color(Color.white.opacity(0.7 * flicker)), lineWidth: 1.2)
        TraceDraw.flare(&ctx, path.sample(at: frame.head), time: time, colors: colors, intensity: flicker, scale: 1.1)
    }
}
#endif
