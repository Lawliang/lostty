#if os(macOS)
import SwiftUI

/// mint-protocol: segmented green packets led by yellow bits.
struct DatastreamTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let packets = 9
        let spacing = frame.length / Double(packets)
        let dash = spacing * 0.55
        for k in 0..<packets {
            let end = frame.head - Double(k) * spacing
            let seg = path.segment(from: end - dash, to: end)
            let color = k < 2 ? colors.tail : colors.head
            let fade = 1 - Double(k) / Double(packets)
            ctx.stroke(seg, with: .color(color.opacity(frame.intensity * fade)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
        }
        TraceDraw.glow(&ctx, at: path.sample(at: frame.head).point, radius: 6, color: colors.tail,
                       opacity: 0.8 * frame.intensity)
    }
}
#endif
