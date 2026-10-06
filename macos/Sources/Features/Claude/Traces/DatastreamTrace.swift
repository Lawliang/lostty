#if os(macOS)
import SwiftUI

/// mint-protocol: bright data packets racing ahead of a light streak.
struct DatastreamTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        TraceDraw.light(&ctx, path, frame: frame, time: time, colors: colors, scale: 0.8, sparkles: false)
        let packets = 8
        let spacing = frame.length / Double(packets)
        let travel = (time * 3).truncatingRemainder(dividingBy: 1) * spacing
        for k in 0..<packets {
            let end = frame.head - Double(k) * spacing + travel - spacing
            let fade = 1 - Double(k) / Double(packets)
            let seg = path.segment(from: end - spacing * 0.5, to: end)
            let color = k < 2 ? colors.tail : colors.head
            var glow = ctx
            glow.addFilter(.blur(radius: 4))
            glow.stroke(seg, with: .color(color.opacity(0.8 * fade * frame.intensity)), lineWidth: 9)
            ctx.stroke(seg, with: .color(Color.white.opacity(0.9 * fade * frame.intensity)), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
        }
    }
}
#endif
