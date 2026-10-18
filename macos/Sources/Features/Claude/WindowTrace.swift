#if os(macOS)
import AppKit
import SwiftUI

/// The website's trace (website/custom.html, "Claude's trace"): a light
/// circling each pane's edge while Claude works in it, in that pane's
/// colors. Shown instead of the skin traces when Lostty → Claude Trace
/// Style is Window Light. A pane where only subagents work keeps its
/// bottom glow.
enum WindowTrace {
    /// One lap, as the website's `ag-spin`.
    static let lapSeconds: Double = 3.2
    /// Showing and going, as the website's opacity transition.
    static let fadeSeconds: Double = 0.5

    /// The website's pink and cyan (`--mk-a1`, `--mk-a2`), for panes with no skin.
    static let websitePink = RGB(hex: "#ff3df2")!
    static let websiteCyan = RGB(hex: "#28e7ff")!

    /// A lit pane's colors.
    struct Lighting: Equatable {
        var pane: UUID
        /// The head's color (the skin's trace color) and the tail's.
        var primary: RGB
        var secondary: RGB

        var colors: TraceColors { TraceColors(primary: primary, secondary: secondary) }
    }

    /// A pane is lit while Claude itself works in it (not only its
    /// subagents), in its skin's trace colors, or the website's with no
    /// skin. Not when its trace is off (`trace = "none"`, `[defaults]
    /// trace = false`).
    static func lighting(pane: UUID, phase: TracePhase, skin: Skin?, enabled: Bool) -> Lighting? {
        guard case .racing(_, false) = phase,
              let trace = ResolvedTrace.resolve(skin: skin, enabled: enabled) else { return nil }
        if skin == nil { return Lighting(pane: pane, primary: websitePink, secondary: websiteCyan) }
        return Lighting(pane: pane, primary: trace.color, secondary: trace.color2)
    }

    /// The light's turn, in degrees clockwise from the top, `elapsed`
    /// seconds after it lit.
    static func angle(elapsed: Double) -> Double {
        let laps = max(0, elapsed) / lapSeconds
        return (laps - laps.rounded(.down)) * 360
    }

    /// Where the website's conic gradient changes, as shares of a turn
    /// from its start: dark, the tail coming in, the head, the white-hot
    /// tip, and dark again just past it.
    static let stopLocations: [Double] = [0, 0.64, 0.80, 0.93, 0.95, 0.96, 1]

    /// The website's gradient: `transparent 0 64%, color-mix(accent2 70%)
    /// 80%, accent 93%, #fff 95%, transparent 96%`.
    static func stops(_ colors: TraceColors) -> [Gradient.Stop] {
        let shades: [Color] = [
            colors.tail.opacity(0), colors.tail.opacity(0), colors.tail.opacity(0.7), colors.head,
            .white, .white.opacity(0), .white.opacity(0),
        ]
        return zip(shades, stopLocations).map { Gradient.Stop(color: $0, location: $1) }
    }
}

/// The light round one pane. Draws nothing until Claude works there.
struct PaneLightView: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowVisible = true
    /// The last lighting, kept while the light fades out.
    @State private var shown: WindowTrace.Lighting?
    @State private var lit = false
    @State private var since = Date()

    private var lighting: WindowTrace.Lighting? {
        WindowTrace.lighting(
            pane: surfaceID, phase: runtime.phase(surfaceID),
            skin: skins.effectiveSkin(surfaceID), enabled: skins.config.trace)
    }

    var body: some View {
        GeometryReader { geo in
            if let shown {
                TimelineView(.animation(paused: !lit || !windowVisible)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(since)
                    if reduceMotion {
                        calm(size: geo.size, colors: shown.colors, elapsed: elapsed)
                    } else {
                        WindowTraceRing(colors: shown.colors, angle: WindowTrace.angle(elapsed: elapsed),
                                        cornerRadius: 0, size: geo.size)
                    }
                }
            }
        }
        .opacity(lit ? 1 : 0)
        .animation(.easeInOut(duration: WindowTrace.fadeSeconds), value: lit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background(OcclusionProbe(visible: $windowVisible))
        .onAppear { light(lighting) }
        .onChange(of: lighting) { light($0) }
    }

    private func light(_ lighting: WindowTrace.Lighting?) {
        if let lighting {
            if !lit { since = Date() }
            shown = lighting
        }
        lit = lighting != nil
    }

    /// Reduce Motion: no circling; the whole edge breathes with a 2s period.
    private func calm(size: CGSize, colors: TraceColors, elapsed: Double) -> some View {
        let breath = 0.25 + 0.35 * (0.5 + 0.5 * sin(2 * .pi * elapsed / 2))
        return Rectangle().strokeBorder(colors.head, lineWidth: 2)
            .opacity(breath)
            .frame(width: size.width, height: size.height)
    }
}

/// One frame of the light: the website's conic gradient turned `angle`
/// round the pane's center, seen through a thin line along the edge and,
/// softer, a glow just inside it (the website's glow spills outside the
/// box; a pane can't draw there).
struct WindowTraceRing: View {
    let colors: TraceColors
    let angle: Double
    let cornerRadius: CGFloat
    let size: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let side = (size.width * size.width + size.height * size.height).squareRoot()
        let sweep = AngularGradient(
            gradient: Gradient(stops: WindowTrace.stops(colors)), center: .center,
            startAngle: .degrees(-90), endAngle: .degrees(270))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(angle))
            .frame(width: size.width, height: size.height)
        ZStack {
            sweep
                .mask(shape.strokeBorder(lineWidth: 12).blur(radius: 9))
                .opacity(0.55)
            sweep
                .mask(shape.strokeBorder(lineWidth: 2))
        }
        .frame(width: size.width, height: size.height)
    }
}

#endif
