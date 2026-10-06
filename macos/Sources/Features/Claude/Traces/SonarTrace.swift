#if os(macOS)
import SwiftUI

/// deep-dive: a cyan flash whose head sends out sonar rings.
struct SonarTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.light(&ctx, path, frame: frame, time: time, colors: colors)
        let head = path.sample(at: frame.head).point
        for ring in 0..<3 {
            let phase = (time * 1.8 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
            let radius = CGFloat(6 + 34 * phase)
            let circle = Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2))
            ctx.stroke(circle, with: .color(colors.tail.opacity((1 - phase) * 0.8 * frame.intensity)), lineWidth: 2)
        }
    }
}
#endif
