#if os(macOS)
import SwiftUI

/// undertow: a sea-foam wave that swells and recedes as it moves.
struct TideTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let swell = 4 + 3 * sin(time * 1.5)
        let steps = 48
        var wave = Path()
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let along = frame.head - frame.length * (1 - t)
            let envelope = sin(.pi * t)
            let lift = swell * envelope * (0.5 + 0.5 * sin(along * path.perimeter / 18 - time * 4))
            let p = path.offsetPoint(at: along, inward: CGFloat(lift))
            if i == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
        }
        var foam = ctx
        foam.addFilter(.blur(radius: 3))
        foam.stroke(wave, with: .color(colors.tail.opacity(0.6 * frame.intensity)), lineWidth: 5)
        ctx.stroke(wave, with: .color(colors.head.opacity(frame.intensity)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
}
#endif
