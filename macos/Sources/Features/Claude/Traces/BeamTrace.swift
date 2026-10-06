#if os(macOS)
import SwiftUI

/// Default: a flash of light streaking along the edge.
struct BeamTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.light(&ctx, path, frame: frame, time: time, colors: colors)
    }
}
#endif
