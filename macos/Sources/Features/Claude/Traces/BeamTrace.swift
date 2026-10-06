#if os(macOS)
import SwiftUI

/// Default: a clean light ray with a soft fading tail.
struct BeamTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.tail(&ctx, path, frame: frame, width: { 1 + 1.5 * $0 }, color: { colors.blend($0) })
        let head = path.sample(at: frame.head).point
        TraceDraw.glow(&ctx, at: head, radius: 7, color: colors.head, opacity: 0.8 * frame.intensity)
        TraceDraw.dot(&ctx, at: head, radius: 1.8, color: .white, opacity: frame.intensity)
    }
}
#endif
