#if os(macOS)
import AppKit
import SwiftUI

/// The Claude trace for one pane (spec §4). Lives in SurfaceWrapper's
/// ZStack; draws nothing (and is not in the tree) while the pane is idle.
struct ClaudeTraceLayer: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @Environment(\.hostsWindowTrace) private var hostsWindowTrace
    @AppStorage(TraceStyle.defaultsKey, store: .ghostty) private var style = TraceStyle.initial

    var body: some View {
        let phase = runtime.phase(surfaceID)
        // In Window Light the window's light stands for Claude working;
        // the pane keeps only its subagents' bottom glow.
        let bottomOnly = hostsWindowTrace && style == .window
        if !phase.isOff, !bottomOnly || phase.subagentsOnly,
           let trace = ResolvedTrace.resolve(skin: skins.effectiveSkin(surfaceID), enabled: skins.config.trace) {
            TraceOverlay(phase: phase, trace: trace, bottomOnly: bottomOnly)
                .allowsHitTesting(false)
        }
    }
}

struct TraceOverlay: View {
    static let inset: CGFloat = 1.5

    let phase: TracePhase
    let trace: ResolvedTrace
    /// Only the subagents' bottom glow, without the racing head.
    var bottomOnly = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TraceRoute.defaultsKey, store: .ghostty) private var route = TraceRoute.initial
    @State private var windowVisible = true
    @State private var journey = Journey()

    /// The head's motion, kept across frames. A class so drawing can
    /// advance it without invalidating the view.
    final class Journey {
        var since: Date?
        var motion = TraceMotion()
    }

    var body: some View {
        TimelineView(.animation(paused: !windowVisible)) { timeline in
            Canvas { ctx, size in
                guard case .racing(let since, let subagents) = phase else { return }
                let rect = Self.edgeRect(size)
                let course: TraceCourse = subagents ? .subagents : .route(route)
                let elapsed = max(0, timeline.date.timeIntervalSince(since))
                let colors = TraceColors(trace)
                let time = timeline.date.timeIntervalSinceReferenceDate
                ctx.blendMode = .plusLighter
                if bottomOnly {
                    Self.drawBottomGlow(in: &ctx, rect: rect, level: TraceFrame.intensity(elapsed: elapsed), colors: colors)
                    return
                }
                if reduceMotion {
                    let intensity = TraceFrame.intensity(elapsed: elapsed)
                    if subagents { Self.drawBottomGlow(in: &ctx, rect: rect, level: intensity, colors: colors) }
                    Self.drawCalmGlow(in: &ctx, outline: course.outline(in: rect), intensity: intensity, time: time, colors: colors)
                    return
                }

                if journey.since != since {
                    journey.since = since
                    journey.motion = TraceMotion()
                }
                let legSeconds = TraceFrame.legSeconds(speed: trace.speed)
                journey.motion.advance(to: elapsed, course: course, legSeconds: legSeconds)
                let path = journey.motion.path(in: rect, at: elapsed, legSeconds: legSeconds)
                guard path.length > 0 else { return }
                // The tail is sized by the person's route, so it keeps its
                // length on the bottom edge; early on it is only as long as
                // the way travelled.
                let tail = min(path.length, trace.length * TraceCourse.route(route).lapLength(in: rect))
                let frame = TraceFrame(head: 1, length: tail / path.length, intensity: TraceFrame.intensity(elapsed: elapsed))
                Self.drawBottomGlow(in: &ctx, rect: rect, level: journey.motion.bottomGlow(at: elapsed) * frame.intensity,
                                    colors: colors)
                TraceRenderers.renderer(for: trace.style)
                    .draw(in: &ctx, along: path, frame: frame, time: time, colors: colors)
            }
        }
        .background(OcclusionProbe(visible: $windowVisible))
    }

    /// The pane's inside edge. Degenerate panes collapse to a point so every
    /// position stays finite.
    static func edgeRect(_ size: CGSize) -> CGRect {
        let width = max(0, size.width - 2 * inset)
        let height = max(0, size.height - 2 * inset)
        guard width > 0, height > 0 else { return CGRect(x: inset, y: inset, width: 0, height: 0) }
        return CGRect(x: inset, y: inset, width: width, height: height)
    }

    /// While only subagents work: light rising into the pane from the bottom
    /// edge, under the trace. A soft band in the trace's colors, brightest
    /// at the edge, with a blurred line along the edge itself.
    static func drawBottomGlow(in ctx: inout GraphicsContext, rect: CGRect, level: Double, colors: TraceColors) {
        guard level > 0, rect.width > 0 else { return }
        let depth = min(56, rect.height * 0.3)
        let band = CGRect(x: rect.minX, y: rect.maxY - depth, width: rect.width, height: depth + inset)
        let rise = Gradient(stops: [
            .init(color: colors.tail.opacity(0), location: 0),
            .init(color: colors.tail.opacity(0.12 * level), location: 0.55),
            .init(color: colors.head.opacity(0.32 * level), location: 1),
        ])
        ctx.fill(Path(band), with: .linearGradient(
            rise, startPoint: CGPoint(x: rect.midX, y: band.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

        var edge = Path()
        edge.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        edge.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        var bloom = ctx
        bloom.addFilter(.blur(radius: 8))
        bloom.stroke(edge, with: .color(colors.head.opacity(0.5 * level)), lineWidth: 10)
    }

    /// Reduce Motion: no racing; the course's edge breathes with a 2s period.
    static func drawCalmGlow(
        in ctx: inout GraphicsContext, outline: Path, intensity: Double, time: Double, colors: TraceColors
    ) {
        let breath = 0.25 + 0.35 * (0.5 + 0.5 * sin(2 * .pi * time / 2))
        ctx.stroke(outline, with: .color(colors.head.opacity(breath * intensity)), lineWidth: 2)
    }
}

/// Reports whether the hosting window is visible (not minimized or fully
/// covered), so the animation can pause.
struct OcclusionProbe: NSViewRepresentable {
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
