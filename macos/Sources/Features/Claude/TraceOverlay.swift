#if os(macOS)
import AppKit
import SwiftUI

/// The Claude trace for one pane (spec §4). Lives in SurfaceWrapper's
/// ZStack; draws nothing (and is not in the tree) while the pane is idle.
struct ClaudeTraceLayer: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        let phase = runtime.phase(surfaceID)
        if !phase.isOff,
           let trace = ResolvedTrace.resolve(skin: skins.effectiveSkin(surfaceID), enabled: skins.config.trace) {
            TraceOverlay(phase: phase, trace: trace)
                .allowsHitTesting(false)
        }
    }
}

struct TraceOverlay: View {
    static let inset: CGFloat = 1.5

    let phase: TracePhase
    let trace: ResolvedTrace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowVisible = true

    var body: some View {
        TimelineView(.animation(paused: !windowVisible)) { timeline in
            Canvas { ctx, size in
                let path = EdgePath(size: size, inset: Self.inset)
                let lap = TraceFrame.lapSeconds(perimeter: path.perimeter, speed: trace.speed)
                guard let frame = TraceFrame.make(phase, now: timeline.date, lapSeconds: lap, length: trace.length) else { return }
                let colors = TraceColors(trace)
                let time = timeline.date.timeIntervalSinceReferenceDate
                ctx.blendMode = .plusLighter
                if reduceMotion {
                    Self.drawCalmGlow(in: &ctx, along: path, frame: frame, time: time, colors: colors)
                } else {
                    TraceRenderers.renderer(for: trace.style)
                        .draw(in: &ctx, along: path, frame: frame, time: time, colors: colors)
                }
                if frame.pulse > 0 {
                    Self.drawPulse(in: &ctx, along: path, frame: frame, colors: colors)
                }
            }
        }
        .background(OcclusionProbe(visible: $windowVisible))
    }

    /// Finish flash: the whole border glows once.
    static func drawPulse(in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, colors: TraceColors) {
        let opacity = frame.pulse * frame.intensity
        var halo = ctx
        halo.addFilter(.blur(radius: 6))
        halo.stroke(path.outline, with: .color(colors.head.opacity(opacity)), lineWidth: 6)
        ctx.stroke(path.outline, with: .color(colors.blend(0.6).opacity(opacity)), lineWidth: 2)
    }

    /// Reduce Motion: no racing; the border breathes with a 2s period.
    static func drawCalmGlow(
        in ctx: inout GraphicsContext, along path: EdgePath, frame: TraceFrame, time: Double, colors: TraceColors
    ) {
        let breath = 0.25 + 0.35 * (0.5 + 0.5 * sin(2 * .pi * time / 2))
        ctx.stroke(path.outline, with: .color(colors.head.opacity(breath * frame.intensity)), lineWidth: 2)
    }
}

/// Reports whether the hosting window is visible (not minimized or fully
/// covered), so the animation can pause.
private struct OcclusionProbe: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> Probe {
        Probe { isVisible in
            DispatchQueue.main.async { if visible != isVisible { visible = isVisible } }
        }
    }

    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        private let onChange: (Bool) -> Void
        private var token: NSObjectProtocol?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                guard let window = self?.window else { return }
                self?.onChange(window.occlusionState.contains(.visible))
            }
            onChange(window.occlusionState.contains(.visible))
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
#endif
