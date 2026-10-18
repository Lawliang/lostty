#if os(macOS)
import AppKit
import SwiftUI

/// A terminal window's Claude trace, round the whole window's edge (title
/// bar included) while Claude works in any of its panes. Skin Traces runs
/// the working pane's skin trace there; Window Light (Lostty → Claude Trace
/// Style) runs the website's light (website/custom.html, "Claude's trace").
/// While only subagents or shells work, either keeps to the bottom edge.
enum WindowTrace {
    /// One lap, as the website's `ag-spin`.
    static let lapSeconds: Double = 3.2
    /// Showing and going, as the website's opacity transition.
    static let fadeSeconds: Double = 0.5

    /// The website's pink and cyan (`--mk-a1`, `--mk-a2`), for panes with no skin.
    static let websitePink = RGB(hex: "#ff3df2")!
    static let websiteCyan = RGB(hex: "#28e7ff")!

    /// The pane whose trace the window shows.
    struct Lighting: Equatable {
        var pane: UUID
        var phase: TracePhase
        var trace: ResolvedTrace
        /// The pane has no skin, so Window Light takes the website's colors.
        var unskinned: Bool

        /// Window Light's head and tail colors.
        var lightColors: TraceColors {
            unskinned ? TraceColors(primary: WindowTrace.websitePink, secondary: WindowTrace.websiteCyan)
                : TraceColors(trace)
        }

        /// Window Light circles the window; only subagents keep to the bottom.
        var circles: Bool { !phase.isOff && !phase.subagentsOnly }
    }

    /// The pane that lights the window: one where Claude itself works
    /// before one where only subagents or shells do, and within each the
    /// focused pane first, then the window's order. Panes whose trace is off
    /// (`trace = "none"`, `[defaults] trace = false`) don't light it.
    static func lighting(
        panes: [UUID], focused: UUID?, phases: [UUID: TracePhase], skin: (UUID) -> Skin?, enabled: Bool
    ) -> Lighting? {
        let order = focused.map { focused in panes.contains(focused) ? [focused] + panes.filter { $0 != focused } : panes } ?? panes
        var subagents: Lighting?
        for pane in order {
            let phase = phases[pane] ?? .off
            guard !phase.isOff else { continue }
            let paneSkin = skin(pane)
            guard let trace = ResolvedTrace.resolve(skin: paneSkin, enabled: enabled) else { continue }
            let lighting = Lighting(pane: pane, phase: phase, trace: trace, unskinned: paneSkin == nil)
            if lighting.circles { return lighting }
            if subagents == nil { subagents = lighting }
        }
        return subagents
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

/// Whether a pane's window draws the window trace, so the pane leaves its
/// own trace out. Only standalone terminal windows do; the Quick Terminal
/// keeps its pane traces.
private struct HostsWindowTraceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hostsWindowTrace: Bool {
        get { self[HostsWindowTraceKey.self] }
        set { self[HostsWindowTraceKey.self] = newValue }
    }
}

/// The window's corner radius, which the trace's edge follows.
@MainActor
final class WindowTraceEdge: ObservableObject {
    @Published var cornerRadius: CGFloat = 0

    func update(from window: NSWindow?) {
        guard let window else { return }
        let radius: CGFloat
        if window.styleMask.contains(.fullScreen) {
            radius = 0
        } else if window.responds(to: Selector(("_cornerRadius"))), let r = window.value(forKey: "_cornerRadius") as? CGFloat {
            radius = r
        } else {
            radius = 10
        }
        if cornerRadius != radius { cornerRadius = radius }
    }
}

/// The trace over one window. Draws nothing until Claude works there.
struct WindowTraceView: View {
    @ObservedObject var controller: BaseTerminalController
    @ObservedObject var sidebar: ExtensionSidebarModel
    @ObservedObject var edge: WindowTraceEdge
    @ObservedObject private var runtime = ClaudeRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @AppStorage(TraceStyle.defaultsKey, store: .ghostty) private var style = TraceStyle.initial
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowVisible = true
    /// Window Light's colors, kept while the light fades out.
    @State private var shown: TraceColors?
    @State private var lit = false
    @State private var since = Date()

    private var lighting: WindowTrace.Lighting? {
        WindowTrace.lighting(
            panes: controller.surfaceTree.map(\.id), focused: sidebar.focusedSurfaceID,
            phases: runtime.phases, skin: { skins.effectiveSkin($0) }, enabled: skins.config.trace)
    }

    /// Window Light circling the window, rather than keeping to the bottom.
    private var circling: WindowTrace.Lighting? {
        guard style == .window, let lighting, lighting.circles else { return nil }
        return lighting
    }

    var body: some View {
        ZStack {
            if let lighting, style == .skin || !lighting.circles {
                TraceOverlay(phase: lighting.phase, trace: lighting.trace, bottomOnly: style == .window,
                             cornerRadius: edge.cornerRadius)
            }
            light
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { light(circling) }
        .onChange(of: circling) { light($0) }
    }

    private var light: some View {
        GeometryReader { geo in
            if let shown {
                TimelineView(.animation(paused: !lit || !windowVisible)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(since)
                    if reduceMotion {
                        calm(size: geo.size, colors: shown, elapsed: elapsed)
                    } else {
                        WindowTraceRing(colors: shown, angle: WindowTrace.angle(elapsed: elapsed),
                                        cornerRadius: edge.cornerRadius, size: geo.size)
                    }
                }
            }
        }
        .opacity(lit ? 1 : 0)
        .animation(.easeInOut(duration: WindowTrace.fadeSeconds), value: lit)
        .background(OcclusionProbe(visible: $windowVisible))
    }

    private func light(_ lighting: WindowTrace.Lighting?) {
        if let lighting {
            if !lit { since = Date() }
            shown = lighting.lightColors
        }
        lit = lighting != nil
    }

    /// Reduce Motion: no circling; the whole edge breathes with a 2s period.
    private func calm(size: CGSize, colors: TraceColors, elapsed: Double) -> some View {
        let breath = 0.25 + 0.35 * (0.5 + 0.5 * sin(2 * .pi * elapsed / 2))
        return RoundedRectangle(cornerRadius: edge.cornerRadius).strokeBorder(colors.head, lineWidth: 2)
            .opacity(breath)
            .frame(width: size.width, height: size.height)
    }
}

/// One frame of the light: the website's conic gradient turned `angle`
/// round the window's center, seen through a thin line along the edge
/// and, softer, a glow just inside it (the website's glow spills outside
/// the window; a window can't draw there).
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

/// Lays the window trace over a terminal window's whole frame, title bar
/// included, without taking clicks.
@MainActor
enum WindowTraceHost {
    static func attach(to window: TerminalWindow, controller: BaseTerminalController) {
        guard let frame = window.contentView?.superview else { return }
        let edge = WindowTraceEdge()
        let host = HostView(
            rootView: WindowTraceView(controller: controller, sidebar: window.extensionSidebarModel, edge: edge),
            edge: edge)
        host.frame = frame.bounds
        host.autoresizingMask = [.width, .height]
        frame.addSubview(host, positioned: .above, relativeTo: nil)
    }

    final class HostView: NSHostingView<WindowTraceView> {
        private var edge: WindowTraceEdge?

        init(rootView: WindowTraceView, edge: WindowTraceEdge) {
            self.edge = edge
            super.init(rootView: rootView)
        }

        required init(rootView: WindowTraceView) {
            super.init(rootView: rootView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            edge?.update(from: window)
        }
    }
}
#endif
