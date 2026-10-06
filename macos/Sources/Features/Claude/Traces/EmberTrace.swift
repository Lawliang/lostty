#if os(macOS)
import SwiftUI

/// lava-rush: a molten head shedding embers that drift into the pane.
struct EmberTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.tail(&ctx, path, frame: frame, width: { 1.5 + 2.5 * $0 }, color: { colors.blend($0 * 0.6 + 0.4) })
        for i in 0..<14 {
            let age = (time * 0.9 + TraceDraw.noise(i, 1)).truncatingRemainder(dividingBy: 1)
            let along = frame.head - frame.length * TraceDraw.noise(i, 2) * (0.3 + age)
            let p = path.offsetPoint(at: along, inward: CGFloat(2 + 14 * age))
            TraceDraw.dot(&ctx, at: p, radius: CGFloat(1.6 * (1 - age) + 0.4), color: colors.tail,
                          opacity: (1 - age) * frame.intensity)
        }
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 10, color: colors.head, opacity: frame.intensity)
        TraceDraw.dot(&ctx, at: head, radius: 2.5, color: colors.tail, opacity: frame.intensity)
    }
}
#endif
