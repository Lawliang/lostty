#if os(macOS)
import SwiftUI

/// deep-dive: a cyan beam whose head sends out rings as it travels.
struct SonarTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.tail(&ctx, path, frame: frame, width: { 1 + 1.5 * $0 }, color: { colors.blend($0) })
        let head = path.sample(at: frame.head).point
        for ring in 0..<3 {
            let phase = (time * 1.2 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
            let radius = CGFloat(3 + 16 * phase)
            let circle = Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2))
            ctx.stroke(circle, with: .color(colors.tail.opacity((1 - phase) * 0.7 * frame.intensity)), lineWidth: 1.2)
        }
        TraceDraw.glow(&ctx, at: head, radius: 7, color: colors.head, opacity: frame.intensity)
    }
}
#endif
