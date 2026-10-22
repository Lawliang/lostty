#if os(macOS)
import AppKit
import SwiftUI

/// A window dropped on the canvas's title bar warping into it, in the
/// spirit of Apple Music's glass (docs/design/apple-music-liquid-glass.md):
/// the window, as a picture, falls into the point it was let go at, the
/// nearest parts first, twisting a little, its colors splitting at the
/// edges (CanvasAbsorb.metal); light gathers at the point, two rings in
/// the glass's colors spread across the title bar like ripples in oil,
/// and the new card springs up on the canvas. Reduce Motion: the window
/// fades, and the card fades in.
@MainActor
enum CanvasAbsorb {
    /// The warp's length; the rings spread for `rippleSeconds` after.
    static let seconds: TimeInterval = 0.62
    static let rippleSeconds: TimeInterval = 0.7
    /// When the card is made: as the window is nearly gone.
    static let arriveAt = 0.8
    /// A window's corners, for its picture.
    static let cornerRadius: CGFloat = 12

    /// Warps `window` into `target` (in screen coordinates), calling
    /// `arrive` once it's nearly gone to put its panes on the canvas.
    static func run(_ window: NSWindow, into target: NSPoint, arrive: @escaping () -> Void) {
        let screen = window.screen ?? NSScreen.main
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let image = snapshot(window), let screen else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated(arrive) })
            return
        }
        let geometry = Geometry(window: window.frame, target: target, screen: screen.frame)
        let panel = overlay(frame: geometry.frame)
        panel.contentView = NSHostingView(rootView: CanvasAbsorbView(
            image: image, scale: window.backingScaleFactor, geometry: geometry, start: Date()))
        panel.orderFrontRegardless()
        // The picture stands in for the window from here.
        window.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds * arriveAt) {
            MainActor.assumeIsolated(arrive)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + rippleSeconds + 0.1) {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    /// Where the warp plays: round the window and the point it falls into,
    /// on its screen; the window and the point in it, y down.
    struct Geometry: Equatable {
        var frame: CGRect
        var window: CGRect
        var target: CGPoint
        /// How far the window's farthest corner is from the point.
        var reach: CGFloat

        /// Room round the window for the rings and the light.
        static let margin: CGFloat = 40
        /// How far the rings spread each way from the point.
        static let rippleRadius: CGFloat = 180

        init(window: CGRect, target: CGPoint, screen: CGRect) {
            let ripples = CGRect(x: target.x - Self.rippleRadius, y: target.y - Self.rippleRadius / 2,
                                 width: Self.rippleRadius * 2, height: Self.rippleRadius)
            var frame = window.union(ripples).insetBy(dx: -Self.margin, dy: -Self.margin).intersection(screen)
            if frame.isNull { frame = window }
            self.frame = frame
            self.window = CGRect(x: window.minX - frame.minX, y: frame.maxY - window.maxY,
                                 width: window.width, height: window.height)
            self.target = CGPoint(x: target.x - frame.minX, y: frame.maxY - target.y)
            let local = self.window, point = self.target
            reach = max(1, [CGPoint(x: local.minX, y: local.minY), CGPoint(x: local.maxX, y: local.minY),
                            CGPoint(x: local.minX, y: local.maxY), CGPoint(x: local.maxX, y: local.maxY)]
                .map { hypot($0.x - point.x, $0.y - point.y) }.max() ?? 1)
        }
    }

    /// The window as it looks now, title bar and all. Its panes draw with
    /// Metal, which caching a view can miss, so each is drawn in again
    /// from its own picture.
    static func snapshot(_ window: NSWindow) -> CGImage? {
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return nil }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        if let controller = window.windowController as? BaseTerminalController,
           let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            for pane in controller.surfaceTree where !pane.isHiddenOrHasHiddenAncestor {
                pane.asImage?.draw(in: pane.convert(pane.bounds, to: frameView))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        return rep.cgImage
    }

    /// The card springs up where it lands, from a little smaller and clear.
    static func emerge(_ view: NSView) {
        guard let layer = view.layer else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.duration = 0.25
            layer.add(fade, forKey: "losttyEmerge")
            return
        }
        // About the card's middle: a view's layer turns about its corner.
        let middle = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
        var small = CATransform3DMakeTranslation(middle.x, middle.y, 0)
        small = CATransform3DScale(small, 0.86, 0.86, 1)
        small = CATransform3DTranslate(small, -middle.x, -middle.y, 0)
        let grow = CASpringAnimation(keyPath: "transform")
        grow.fromValue = small
        grow.toValue = CATransform3DIdentity
        grow.mass = 1
        grow.stiffness = 260
        grow.damping = 20
        grow.duration = grow.settlingDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.22
        layer.add(grow, forKey: "losttyEmerge")
        layer.add(fade, forKey: "losttyEmergeFade")
    }

    /// A clear window over everything that clicks pass through.
    static func overlay(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return panel
    }
}

/// The warp, its light and its rings, each frame from the time since it
/// began.
private struct CanvasAbsorbView: View {
    let image: CGImage
    let scale: CGFloat
    let geometry: CanvasAbsorb.Geometry
    let start: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let progress = min(1, elapsed / CanvasAbsorb.seconds)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .frame(width: geometry.window.width, height: geometry.window.height)
                    .clipShape(RoundedRectangle(cornerRadius: CanvasAbsorb.cornerRadius, style: .continuous))
                    .offset(x: geometry.window.minX, y: geometry.window.minY)
                    .frame(width: geometry.frame.width, height: geometry.frame.height, alignment: .topLeading)
                    .layerEffect(
                        ShaderLibrary.losttyAbsorb(
                            .float2(geometry.target), .float(progress), .float(geometry.reach)),
                        maxSampleOffset: geometry.frame.size)
                CanvasAbsorbLight(progress: progress, elapsed: elapsed)
                    .position(geometry.target)
            }
            .frame(width: geometry.frame.width, height: geometry.frame.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }
}

/// Light gathering where the window falls in, then two rings spreading
/// from it across the title bar, wide and flat, in the glass's colors.
private struct CanvasAbsorbLight: View {
    let progress: Double
    let elapsed: TimeInterval

    /// Cyan into blue with a warm fringe: the + button's prism.
    private static let prism = AngularGradient(
        colors: [.cyan, .blue, Color(red: 0.35, green: 0.25, blue: 0.95), .white,
                 Color(red: 1, green: 0.45, blue: 0.2), .cyan],
        center: .center)

    var body: some View {
        // Brightest just as the window's gone, then fading.
        let gather = smoothstep(0.35, 0.92, progress) * (1 - smoothstep(0, 0.35, elapsed - CanvasAbsorb.seconds))
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white, .cyan.opacity(0.7), .blue.opacity(0.25), .clear],
                                     center: .center, startRadius: 0, endRadius: 28))
                .frame(width: 56, height: 56)
                .scaleEffect(0.4 + 0.8 * gather)
                .opacity(gather)
                .blendMode(.plusLighter)
            ring(delay: 0)
            ring(delay: 0.12)
        }
        .frame(width: CanvasAbsorb.Geometry.rippleRadius * 2, height: CanvasAbsorb.Geometry.rippleRadius)
    }

    /// One ring, from as the window's nearly gone.
    private func ring(delay: TimeInterval) -> some View {
        let local = (elapsed - CanvasAbsorb.seconds * CanvasAbsorb.arriveAt - delay) / CanvasAbsorb.rippleSeconds
        let shown = local > 0 && local < 1
        let spread = 1 - pow(1 - min(max(local, 0), 1), 3)
        return Ellipse()
            .stroke(Self.prism, lineWidth: 1.4)
            .frame(width: 40, height: 14)
            .scaleEffect(1 + 7 * spread)
            .opacity(shown ? 0.9 * (1 - local) : 0)
            .blendMode(.plusLighter)
    }

    private func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let x = min(max((value - low) / (high - low), 0), 1)
        return x * x * (3 - 2 * x)
    }
}
#endif
