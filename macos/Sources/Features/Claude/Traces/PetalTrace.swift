#if os(macOS)
import SwiftUI

/// heartsease: a soft rose glow trailing drifting petals.
struct PetalTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var soft = ctx
        soft.addFilter(.blur(radius: 4))
        TraceDraw.tail(&soft, path, frame: frame, width: { 2 + 5 * $0 }, color: { colors.blend($0) })
        for i in 0..<8 {
            let drift = (time * 0.5 + TraceDraw.noise(i, 3)).truncatingRemainder(dividingBy: 1)
            let along = frame.head - frame.length * (0.15 + 0.85 * TraceDraw.noise(i, 4))
            let p = path.offsetPoint(at: along, inward: CGFloat(3 + 12 * drift))
            var petal = ctx
            petal.translateBy(x: p.x, y: p.y)
            petal.rotate(by: .radians(time * 2 + Double(i)))
            let color = i.isMultiple(of: 2) ? colors.head : colors.tail
            petal.fill(Path(ellipseIn: CGRect(x: -3, y: -1.5, width: 6, height: 3)),
                       with: .color(color.opacity((1 - drift) * frame.intensity)))
        }
        TraceDraw.glow(&ctx, at: path.sample(at: frame.head).point, radius: 9, color: colors.head,
                       opacity: 0.9 * frame.intensity)
    }
}
#endif
