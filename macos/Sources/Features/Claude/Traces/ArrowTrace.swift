#if os(macOS)
import SwiftUI

/// silverbow: a thin silver-green streak with a twinkling starry tail.
struct ArrowTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.tail(&ctx, path, frame: frame, width: { _ in 1.2 }, color: { colors.blend($0) })
        for i in 0..<10 {
            let along = frame.head - frame.length * TraceDraw.noise(i, 5)
            let p = path.offsetPoint(at: along, inward: CGFloat(2 + 6 * TraceDraw.noise(i, 6)))
            let twinkle = 0.5 + 0.5 * sin(time * 6 + Double(i) * 1.7)
            let r = CGFloat(1 + 1.5 * twinkle)
            var star = Path()
            star.move(to: CGPoint(x: p.x - r, y: p.y))
            star.addLine(to: CGPoint(x: p.x + r, y: p.y))
            star.move(to: CGPoint(x: p.x, y: p.y - r))
            star.addLine(to: CGPoint(x: p.x, y: p.y + r))
            ctx.stroke(star, with: .color(colors.tail.opacity(twinkle * frame.intensity)), lineWidth: 0.8)
        }
        let head = path.sample(at: frame.head)
        var tip = Path()
        let back = CGPoint(x: head.point.x - head.tangent.dx * 6, y: head.point.y - head.tangent.dy * 6)
        tip.move(to: head.point)
        tip.addLine(to: CGPoint(x: back.x + head.normal.dx * 3, y: back.y + head.normal.dy * 3))
        tip.addLine(to: CGPoint(x: back.x - head.normal.dx * 3, y: back.y - head.normal.dy * 3))
        tip.closeSubpath()
        ctx.fill(tip, with: .color(colors.head.opacity(frame.intensity)))
        TraceDraw.glow(&ctx, at: head.point, radius: 6, color: colors.head, opacity: 0.8 * frame.intensity)
    }
}
#endif
