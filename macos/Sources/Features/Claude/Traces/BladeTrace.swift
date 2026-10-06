#if os(macOS)
import SwiftUI

/// bloodrite: a short, sharp red slash throwing orange sparks.
struct BladeTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var short = frame
        short.length = frame.length * 0.6
        TraceDraw.tail(&ctx, path, frame: short, width: { 0.5 + 3.5 * $0 }, color: { _ in colors.head })
        TraceDraw.tail(&ctx, path, frame: short, width: { 0.8 * $0 }, color: { _ in .white })
        let head = path.sample(at: frame.head)
        let burst = Int(time / 0.1)
        for i in 0..<6 {
            let angle = CGFloat((TraceDraw.noise(i, burst) - 0.5) * .pi * 0.9)
            let length = CGFloat(4 + 8 * TraceDraw.noise(i, burst + 7))
            let dx = head.normal.dx * cos(angle) - head.normal.dy * sin(angle)
            let dy = head.normal.dx * sin(angle) + head.normal.dy * cos(angle)
            var spark = Path()
            spark.move(to: head.point)
            spark.addLine(to: CGPoint(x: head.point.x + dx * length, y: head.point.y + dy * length))
            ctx.stroke(spark, with: .color(colors.tail.opacity(frame.intensity)), lineWidth: 1)
        }
    }
}
#endif
