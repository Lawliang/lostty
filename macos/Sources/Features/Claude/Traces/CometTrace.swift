#if os(macOS)
import SwiftUI

/// neon-arcade: magenta head, wide cyan glowing tail.
struct CometTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var halo = ctx
        halo.addFilter(.blur(radius: 5))
        TraceDraw.tail(&halo, path, frame: frame, width: { 2 + 6 * $0 }, color: { colors.blend($0) })
        TraceDraw.tail(&ctx, path, frame: frame, width: { 0.5 + 2 * $0 }, color: { colors.blend($0) })
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 12, color: colors.head, opacity: frame.intensity)
        TraceDraw.dot(&ctx, at: head, radius: 2.5, color: .white, opacity: frame.intensity)
    }
}
#endif
