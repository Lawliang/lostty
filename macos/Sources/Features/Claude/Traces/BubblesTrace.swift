#if os(macOS)
import SwiftUI

/// bubble-pop: a chain of pink dots; the last ones pop into yellow sparkles.
struct BubblesTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let count = 10
        for k in 0..<count {
            let t = 1 - Double(k) / Double(count)
            let along = frame.head - frame.length * (1 - t)
            let wobble = CGFloat(sin(time * 6 + Double(k))) * 1.5
            let p = path.offsetPoint(at: along, inward: 3 + wobble)
            if k >= count - 3 {
                let pop = (time * 3 + Double(k)).truncatingRemainder(dividingBy: 1)
                let r = CGFloat(2 + 4 * pop)
                var spark = Path()
                spark.move(to: CGPoint(x: p.x - r, y: p.y))
                spark.addLine(to: CGPoint(x: p.x + r, y: p.y))
                spark.move(to: CGPoint(x: p.x, y: p.y - r))
                spark.addLine(to: CGPoint(x: p.x, y: p.y + r))
                ctx.stroke(spark, with: .color(colors.tail.opacity((1 - pop) * frame.intensity)), lineWidth: 1)
            } else {
                TraceDraw.dot(&ctx, at: p, radius: CGFloat(1.2 + 2.2 * t), color: colors.head, opacity: t * frame.intensity)
            }
        }
        TraceDraw.glow(&ctx, at: path.sample(at: frame.head).point, radius: 7, color: colors.head, opacity: frame.intensity)
    }
}
#endif
