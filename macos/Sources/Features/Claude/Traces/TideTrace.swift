#if os(macOS)
import SwiftUI

/// undertow: a sea-foam wave of light that swells as it rolls.
struct TideTrace: TraceRenderer {
    func draw(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors) {
        let swell = 9 + 5 * sin(time * 2.5)
        let steps = 56
        var wave = Path()
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let along = frame.head - frame.length * (1 - t)
            let envelope = sin(.pi * t)
            let lift = swell * envelope * (0.5 + 0.5 * sin(along * path.perimeter / 26 - time * 9))
            let p = path.offsetPoint(at: along, inward: CGFloat(lift))
            if i == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
        }
        var foam = ctx
        foam.addFilter(.blur(radius: 8))
        foam.stroke(wave, with: .color(colors.tail.opacity(0.7 * frame.intensity)), lineWidth: 16)
        var glow = ctx
        glow.addFilter(.blur(radius: 2))
        glow.stroke(wave, with: .color(colors.head.opacity(frame.intensity)), lineWidth: 5)
        ctx.stroke(wave, with: .color(Color.white.opacity(0.8 * frame.intensity)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        TraceDraw.flare(&ctx, path.sample(at: frame.head), time: time, colors: colors, intensity: frame.intensity)
    }
}
#endif
