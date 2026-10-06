#if os(macOS)
import SwiftUI

/// sunset-drive: a long orange→pink sweep cut into scanline bands.
struct SunsetTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        var long = frame
        long.length = min(1, frame.length * 1.6)
        TraceDraw.tail(&ctx, path, frame: long, pieces: 40, width: { _ in 3 }, color: { t in
            let band = Int(t * 40) % 2 == 0 ? 1.0 : 0.35
            return colors.blend(t).opacity(band)
        })
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 9, color: colors.head, opacity: frame.intensity)
    }
}
#endif
