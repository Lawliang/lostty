#if os(macOS)
import SwiftUI

/// neon-arcade: an oversized neon comet with a wide magenta-to-cyan bloom.
struct CometTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var halo = ctx
        halo.addFilter(.blur(radius: 16))
        TraceDraw.tail(&halo, path, frame: frame, width: { 30 * CGFloat(TraceDraw.falloff($0)) },
                       color: { colors.blend($0).opacity(0.45 * TraceDraw.falloff($0)) })
        TraceDraw.light(&ctx, path, frame: frame, time: time, colors: colors, scale: 1.25)
    }
}
#endif
