#if os(macOS)
import SwiftUI

/// thunderhead: forked gold lightning that re-strikes every 80ms.
struct BoltTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let strike = Int(time / 0.08)
        let pieces = 16
        let start = frame.head - frame.length
        var bolt = Path()
        var fork = Path()
        for i in 0...pieces {
            let t = Double(i) / Double(pieces)
            // Jagged inward offsets, calmer near the head so it stays on the edge.
            let jitter = i == pieces ? 0 : CGFloat(TraceDraw.noise(i, strike)) * 9 * CGFloat(1 - t * 0.7)
            let p = path.offsetPoint(at: start + frame.length * t, inward: jitter)
            if i == 0 { bolt.move(to: p) } else { bolt.addLine(to: p) }
            if i == pieces / 2 {
                fork.move(to: p)
                let reach = jitter + 10 + CGFloat(TraceDraw.noise(i, strike + 1)) * 8
                fork.addLine(to: path.offsetPoint(at: start + frame.length * (t - 0.08), inward: reach))
            }
        }
        let flicker = frame.intensity * (0.7 + 0.3 * TraceDraw.noise(0, strike))
        var halo = ctx
        halo.addFilter(.blur(radius: 4))
        halo.stroke(bolt, with: .color(colors.tail.opacity(0.6 * flicker)), lineWidth: 5)
        ctx.stroke(bolt, with: .color(colors.head.opacity(flicker)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .bevel))
        ctx.stroke(fork, with: .color(colors.head.opacity(0.7 * flicker)), lineWidth: 1)
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 8, color: colors.head, opacity: flicker)
        TraceDraw.dot(&ctx, at: head, radius: 2, color: .white, opacity: flicker)
    }
}
#endif
