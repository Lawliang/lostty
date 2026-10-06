#if os(macOS)
import SwiftUI

/// sunset-drive: a long orange→pink sweep sliced by moving scanlines.
struct SunsetTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var long = frame
        long.length = min(1, frame.length * 1.5)
        TraceDraw.light(&ctx, path, frame: long, time: time, colors: colors, sparkles: false)
        let shift = time * 6
        TraceDraw.tail(&ctx, path, frame: long, pieces: 36, width: { 9 * CGFloat(TraceDraw.falloff($0)) + 2 }, color: { t in
            let band = (Int(t * 36 + shift) % 3 == 0) ? 0.55 : 0
            return colors.blend(t).opacity(band * TraceDraw.falloff(t))
        })
    }
}
#endif
