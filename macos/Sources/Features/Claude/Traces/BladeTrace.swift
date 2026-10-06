#if os(macOS)
import SwiftUI

/// bloodrite: a short razor-bright slash throwing sparks.
struct BladeTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var short = frame
        short.length = frame.length * 0.55
        TraceDraw.light(&ctx, path, frame: short, time: time, colors: colors, scale: 1.15, sparkles: false)
        let head = path.sample(at: frame.head)
        let burst = Int(time / 0.06)
        for i in 0..<8 {
            let angle = CGFloat((TraceDraw.noise(i, burst) - 0.5) * .pi * 0.9)
            let length = CGFloat(8 + 18 * TraceDraw.noise(i, burst + 7))
            let dx = head.normal.dx * cos(angle) - head.normal.dy * sin(angle)
            let dy = head.normal.dx * sin(angle) + head.normal.dy * cos(angle)
            var spark = Path()
            spark.move(to: head.point)
            spark.addLine(to: CGPoint(x: head.point.x + dx * length, y: head.point.y + dy * length))
            ctx.stroke(spark, with: .color(colors.tail.opacity(frame.intensity)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }
}
#endif
