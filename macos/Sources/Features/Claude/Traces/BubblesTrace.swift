#if os(macOS)
import SwiftUI

/// bubble-pop: a light streak trailing bubbles that pop into sparkles.
struct BubblesTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.light(&ctx, path, frame: frame, time: time, colors: colors, scale: 0.85, sparkles: false)
        let count = 9
        for k in 0..<count {
            let t = 1 - Double(k) / Double(count)
            let along = frame.head - frame.length * (1 - t)
            let wobble = CGFloat(sin(time * 9 + Double(k))) * 3
            let p = path.offsetPoint(at: along, inward: 8 + wobble)
            if k >= count - 3 {
                let pop = (time * 4 + Double(k)).truncatingRemainder(dividingBy: 1)
                let r = CGFloat(4 + 8 * pop)
                var spark = Path()
                spark.move(to: CGPoint(x: p.x - r, y: p.y))
                spark.addLine(to: CGPoint(x: p.x + r, y: p.y))
                spark.move(to: CGPoint(x: p.x, y: p.y - r))
                spark.addLine(to: CGPoint(x: p.x, y: p.y + r))
                ctx.stroke(spark, with: .color(colors.tail.opacity((1 - pop) * frame.intensity)), lineWidth: 1.6)
            } else {
                let r = CGFloat(2.5 + 4 * t)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(colors.head.opacity(t * frame.intensity)), lineWidth: 1.6)
                TraceDraw.dot(&ctx, at: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.35), radius: r * 0.25, color: .white,
                              opacity: t * frame.intensity)
            }
        }
    }
}
#endif
