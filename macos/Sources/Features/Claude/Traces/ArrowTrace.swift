#if os(macOS)
import SwiftUI

/// silverbow: a slim, fast arrow of light with a starry wake.
struct ArrowTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.light(&ctx, path, frame: frame, time: time, colors: colors, scale: 0.85, sparkles: false)
        for i in 0..<12 {
            let along = frame.head - frame.length * TraceDraw.noise(i, 5)
            let p = path.offsetPoint(at: along, inward: CGFloat(4 + 14 * TraceDraw.noise(i, 6)))
            let twinkle = 0.5 + 0.5 * sin(time * 10 + Double(i) * 1.7)
            let r = CGFloat(2 + 3 * twinkle)
            var star = Path()
            star.move(to: CGPoint(x: p.x - r, y: p.y))
            star.addLine(to: CGPoint(x: p.x + r, y: p.y))
            star.move(to: CGPoint(x: p.x, y: p.y - r))
            star.addLine(to: CGPoint(x: p.x, y: p.y + r))
            ctx.stroke(star, with: .color(colors.tail.opacity(twinkle * frame.intensity)), lineWidth: 1.2)
        }
        let head = path.sample(at: frame.head)
        let tipLength: CGFloat = 14, half: CGFloat = 6
        let back = CGPoint(x: head.point.x - head.tangent.dx * tipLength, y: head.point.y - head.tangent.dy * tipLength)
        var tip = Path()
        tip.move(to: CGPoint(x: head.point.x + head.tangent.dx * 4, y: head.point.y + head.tangent.dy * 4))
        tip.addLine(to: CGPoint(x: back.x + head.normal.dx * half, y: back.y + head.normal.dy * half))
        tip.addLine(to: CGPoint(x: back.x - head.normal.dx * half, y: back.y - head.normal.dy * half))
        tip.closeSubpath()
        ctx.fill(tip, with: .color(colors.head.opacity(frame.intensity)))
    }
}
#endif
