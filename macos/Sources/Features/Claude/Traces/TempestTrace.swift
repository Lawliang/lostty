#if os(macOS)
import SwiftUI

/// stormsurge: a gold bolt riding a teal wave.
struct TempestTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TideTrace().draw(in: &ctx, along: path, frame: frame, time: time, colors: colors.swapped())
        var bolt = frame
        bolt.length = frame.length * 0.6
        BoltTrace().draw(in: &ctx, along: path, frame: bolt, time: time, colors: colors)
    }
}
#endif
