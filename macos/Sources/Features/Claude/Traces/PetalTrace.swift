#if os(macOS)
import SwiftUI

/// heartsease: a soft rose flash shedding drifting petals.
struct PetalTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.light(&ctx, path, frame: frame, time: time, colors: colors, sparkles: false)
        for i in 0..<10 {
            let drift = (time * 0.9 + TraceDraw.noise(i, 3)).truncatingRemainder(dividingBy: 1)
            let along = frame.head - frame.length * (0.1 + 0.9 * TraceDraw.noise(i, 4))
            let p = path.offsetPoint(at: along, inward: CGFloat(6 + 26 * drift))
            var petal = ctx
            petal.translateBy(x: p.x, y: p.y)
            petal.rotate(by: .radians(time * 3 + Double(i)))
            let color = i.isMultiple(of: 2) ? colors.head : colors.tail
            petal.fill(Path(ellipseIn: CGRect(x: -6, y: -3, width: 12, height: 6)),
                       with: .color(color.opacity((1 - drift) * frame.intensity)))
        }
    }
}
#endif
