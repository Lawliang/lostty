#if os(macOS)
import SwiftUI

/// lava-rush: a molten flash shedding glowing embers into the pane.
struct EmberTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.light(&ctx, path, frame: frame, time: time, colors: colors, scale: 1.1, sparkles: false)
        for i in 0..<18 {
            let age = (time * 1.4 + TraceDraw.noise(i, 1)).truncatingRemainder(dividingBy: 1)
            let along = frame.head - frame.length * TraceDraw.noise(i, 2) * (0.2 + 0.8 * age)
            let p = path.offsetPoint(at: along, inward: CGFloat(4 + 30 * age))
            TraceDraw.glow(&ctx, at: p, radius: 6, color: colors.tail, opacity: 0.6 * (1 - age) * frame.intensity)
            TraceDraw.dot(&ctx, at: p, radius: CGFloat(2.6 * (1 - age) + 0.6), color: colors.tail, opacity: (1 - age) * frame.intensity)
        }
    }
}
#endif
