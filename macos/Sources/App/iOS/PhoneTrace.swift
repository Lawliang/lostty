#if os(iOS)
import LosttyRemote
import SwiftUI

/// The Mac's Claude trace, around the whole phone: while Claude works, the
/// beam races around the screen's edge, rounded corners and all; while only
/// its subagents work, it bounces back and forth along the bottom edge
/// over a glow, as on the Mac. With the keyboard up, the keyboard's top is
/// the bottom edge (square-cornered, as the keyboard is): the beam runs
/// along it, never behind it. Drawn with the Mac's beam (`TraceDraw`), in
/// the session's skin colors.
struct PhoneTrace: View {
    /// What the session's Claude is doing; nothing shows unless it works.
    let activity: ClaudeActivity?
    let skin: SessionSkin?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the current run (working or subagents) began, for the fade in
    /// and the motion's start.
    @State private var since: Date?

    var body: some View {
        Group {
            if let since, let activity, activity.isWorking {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        // Shorter than the screen: the keyboard takes the rest.
                        let radius = PhoneTraceCourse.screenCornerRadius
                        let overKeyboard = size.height < PhoneTraceCourse.screenHeight - 1
                        let course = PhoneTraceCourse(
                            size: size, cornerRadius: radius, bottomCornerRadius: overKeyboard ? 0 : radius)
                        let elapsed = max(0, timeline.date.timeIntervalSince(since))
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let intensity = TraceFrame.intensity(elapsed: elapsed)
                        let colors = Self.colors(skin)
                        ctx.blendMode = .plusLighter
                        let subagents = activity == .subagents
                        if reduceMotion {
                            let breath = 0.25 + 0.35 * (0.5 + 0.5 * sin(2 * .pi * time / 2))
                            let outline = subagents ? course.bottomLine : course.outline
                            ctx.stroke(outline, with: .color(colors.head.opacity(breath * intensity)), lineWidth: 2)
                            return
                        }
                        let path = subagents ? course.bounce(at: elapsed) : course.lap(at: elapsed)
                        guard path.length > 0 else { return }
                        if subagents {
                            Self.drawBottomGlow(in: &ctx, course: course, level: min(1, elapsed / 0.4) * intensity, colors: colors)
                        }
                        TraceDraw.light(&ctx, path, frame: TraceFrame(head: 1, length: 1, intensity: intensity),
                                        time: time, colors: colors)
                    }
                }
            }
        }
        // Up to the screen's edges, but not under the keyboard.
        .ignoresSafeArea(.container)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { restart(activity) }
        .onChange(of: activity) { old, new in
            // Working and subagents-only are one run each: a switch between
            // them starts the new motion, as on the Mac.
            if old != new { restart(new) }
        }
    }

    private func restart(_ activity: ClaudeActivity?) {
        since = activity?.isWorking == true ? Date() : nil
    }

    /// The skin's accent and a lighter second color, as the Mac picks them;
    /// Lostty's hologram pink and cyan without a skin.
    static func colors(_ skin: SessionSkin?) -> TraceColors {
        guard let skin else {
            return TraceColors(primary: RGB(r: 0xff, g: 0x7a, b: 0xd9), secondary: RGB(r: 0x7a, g: 0xf0, b: 0xff))
        }
        let accent = RGB(r: skin.accent.r, g: skin.accent.g, b: skin.accent.b)
        return TraceColors(primary: accent, secondary: accent.mixed(with: .white, amount: 0.4))
    }

    /// Light rising from the bottom edge while only subagents work, as on
    /// the Mac: a soft band brightest at the edge, and a blurred line.
    static func drawBottomGlow(in ctx: inout GraphicsContext, course: PhoneTraceCourse, level: Double, colors: TraceColors) {
        guard level > 0 else { return }
        let bottom = course.size.height - PhoneTraceCourse.inset
        let depth: CGFloat = 56
        let band = CGRect(x: 0, y: bottom - depth, width: course.size.width, height: depth + PhoneTraceCourse.inset)
        let rise = Gradient(stops: [
            .init(color: colors.tail.opacity(0), location: 0),
            .init(color: colors.tail.opacity(0.12 * level), location: 0.55),
            .init(color: colors.head.opacity(0.32 * level), location: 1),
        ])
        ctx.fill(Path(band), with: .linearGradient(
            rise, startPoint: CGPoint(x: band.midX, y: band.minY), endPoint: CGPoint(x: band.midX, y: bottom)))
        var bloom = ctx
        bloom.addFilter(.blur(radius: 8))
        bloom.stroke(course.bottomLine, with: .color(colors.head.opacity(0.5 * level)), lineWidth: 10)
    }
}

/// A working session's row in the list: a small beam lapping its edge, the
/// screen's trace in miniature, in the session's skin colors. Under Reduce
/// Motion the edge breathes instead.
struct RowTrace: View {
    /// A lap takes as long as the screen's, so the beam goes slower.
    static let lapSeconds = 4 * PhoneTraceCourse.legSeconds
    /// The tail, in points.
    static let tail: Double = 160
    /// The row's corners, as `SessionRowView` rounds them.
    static let cornerRadius: CGFloat = 16
    /// The beam's size against the screen's.
    static let scale: CGFloat = 0.45

    let skin: SessionSkin?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var since = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let course = PhoneTraceCourse(size: size, cornerRadius: Self.cornerRadius)
                let elapsed = max(0, timeline.date.timeIntervalSince(since))
                let time = timeline.date.timeIntervalSinceReferenceDate
                let intensity = TraceFrame.intensity(elapsed: elapsed)
                let colors = PhoneTrace.colors(skin)
                ctx.blendMode = .plusLighter
                if reduceMotion {
                    let breath = 0.2 + 0.3 * (0.5 + 0.5 * sin(2 * .pi * time / 2))
                    ctx.stroke(course.outline, with: .color(colors.head.opacity(breath * intensity)), lineWidth: 1)
                    return
                }
                let path = course.lap(at: elapsed, lapSeconds: Self.lapSeconds, tail: Self.tail)
                guard path.length > 0 else { return }
                TraceDraw.light(&ctx, path, frame: TraceFrame(head: 1, length: 1, intensity: intensity),
                                time: time, colors: colors, scale: Self.scale, sparkles: false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { since = Date() }
    }
}

/// The screen's edge as a rounded rectangle (its bottom corners square over
/// a keyboard), and where the trace's head is on it at a moment, as the
/// stretch it has travelled (an `EdgePath` ending at the head) for
/// `TraceDraw` to draw.
struct PhoneTraceCourse {
    static let inset: CGFloat = 1.5
    /// One trip along a side takes this long on the Mac; a lap here is four.
    static let legSeconds = TraceFrame.legSeconds(speed: 1)
    /// The tail: this share of a lap, as the Mac's default.
    static let tailShare = 0.18

    let size: CGSize
    /// The top corners' radius.
    let radius: CGFloat
    /// The bottom corners': the same, or none over a keyboard.
    let bottomRadius: CGFloat

    init(size: CGSize, cornerRadius: CGFloat, bottomCornerRadius: CGFloat? = nil) {
        self.size = size
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: Self.inset, dy: Self.inset)
        func fit(_ r: CGFloat) -> CGFloat { max(0, min(r - Self.inset, min(rect.width, rect.height) / 2)) }
        radius = fit(cornerRadius)
        bottomRadius = fit(bottomCornerRadius ?? cornerRadius)
    }

    /// This phone's screen corner radius (iOS doesn't say it publicly).
    @MainActor static var screenCornerRadius: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return cornerRadius(safeTop: window?.safeAreaInsets.top ?? 0)
    }

    /// The screen's height, which the trace's canvas falls short of by the
    /// keyboard's.
    @MainActor static var screenHeight: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return window?.bounds.height ?? .infinity
    }

    /// The screen's corner radius: phones with a Dynamic Island have about
    /// 55pt, notched ones about 47pt, and older ones none. Told apart by the
    /// top safe area.
    static func cornerRadius(safeTop: CGFloat) -> CGFloat {
        switch safeTop {
        case 55...: 55
        case 40...: 47.33
        default: 0
        }
    }

    private var rect: CGRect { CGRect(origin: .zero, size: size).insetBy(dx: Self.inset, dy: Self.inset) }

    /// The edge all the way round.
    var outline: Path {
        UnevenRoundedRectangle(
            topLeadingRadius: radius, bottomLeadingRadius: bottomRadius, bottomTrailingRadius: bottomRadius,
            topTrailingRadius: radius, style: .circular
        ).path(in: rect)
    }

    /// The bottom edge between its corners.
    var bottomLine: Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY))
        return path
    }

    var perimeter: Double {
        let r = Double(radius), rb = Double(bottomRadius)
        return 2 * Double(rect.width) - 2 * r - 2 * rb + 2 * (Double(rect.height) - r - rb) + .pi * (r + rb)
    }

    /// The point `distance` along the edge, clockwise from the top edge's
    /// start, with its direction and the way into the screen.
    func sample(_ distance: Double) -> EdgePath.Sample {
        let r = Double(radius), rb = Double(bottomRadius)
        let top = Double(rect.width) - 2 * r, bottom = Double(rect.width) - 2 * rb
        let h = Double(rect.height) - r - rb
        let arc = .pi / 2 * r, bottomArc = .pi / 2 * rb
        var d = distance.truncatingRemainder(dividingBy: perimeter)
        if d < 0 { d += perimeter }
        let x0 = Double(rect.minX), y0 = Double(rect.minY), x1 = Double(rect.maxX), y1 = Double(rect.maxY)
        func straight(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double) -> EdgePath.Sample {
            EdgePath.Sample(point: CGPoint(x: x, y: y), tangent: CGVector(dx: tx, dy: ty), normal: CGVector(dx: -ty, dy: tx))
        }
        /// Around a corner of radius `r` centred at (cx, cy), from angle
        /// `a0` turning clockwise (on screen) by `t` of a quarter turn.
        func corner(_ cx: Double, _ cy: Double, _ r: Double, _ a0: Double, _ t: Double) -> EdgePath.Sample {
            let a = a0 + t * .pi / 2
            let p = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            let tangent = CGVector(dx: -sin(a), dy: cos(a))
            return EdgePath.Sample(point: p, tangent: tangent, normal: CGVector(dx: -cos(a), dy: -sin(a)))
        }
        if d < top { return straight(x0 + r + d, y0, 1, 0) }
        d -= top
        if d < arc { return corner(x1 - r, y0 + r, r, -.pi / 2, d / arc) }
        d -= arc
        if d < h { return straight(x1, y0 + r + d, 0, 1) }
        d -= h
        if d < bottomArc { return corner(x1 - rb, y1 - rb, rb, 0, d / bottomArc) }
        d -= bottomArc
        if d < bottom { return straight(x1 - rb - d, y1, -1, 0) }
        d -= bottom
        if d < bottomArc { return corner(x0 + rb, y1 - rb, rb, .pi / 2, d / bottomArc) }
        d -= bottomArc
        if d < h { return straight(x0, y1 - rb - d, 0, -1) }
        d -= h
        return corner(x0 + r, y0 + r, r, .pi, min(1, d / max(arc, 0.0001)))
    }

    /// Claude working: once round per `lapSeconds` (for the screen, four
    /// of the Mac's legs), the tail `tail` points long (else the Mac's
    /// share of a lap) but no longer than the way travelled.
    func lap(at elapsed: Double, lapSeconds: Double = 4 * Self.legSeconds, tail: Double? = nil) -> EdgePath {
        let head = elapsed / lapSeconds * perimeter
        let tail = min(head, tail ?? Self.tailShare * perimeter)
        return path(along: { sample($0) }, from: head - tail, to: head)
    }

    /// Only subagents working: back and forth along the bottom edge, each
    /// way one of the Mac's legs, eased to rest at both ends. The tail is
    /// where the head has been, so it folds back at each turn.
    func bounce(at elapsed: Double) -> EdgePath {
        let left = Double(rect.minX + bottomRadius), right = Double(rect.maxX - bottomRadius)
        let y = rect.maxY
        func x(_ t: Double) -> Double {
            let legs = max(0, t) / Self.legSeconds
            let leg = Int(legs)
            let u = legs - Double(leg)
            let eased = (1 - cos(.pi * u)) / 2
            // Right to left first, as the Mac's subagents course starts.
            return leg % 2 == 0 ? right - (right - left) * eased : left + (right - left) * eased
        }
        // Walk back in time until the tail is long enough.
        let tail = Self.tailShare * perimeter
        let step = 1.0 / 120
        var points = [CGPoint(x: x(elapsed), y: y)]
        var travelled = 0.0, t = elapsed
        while travelled < tail, t > 0 {
            t = max(0, t - step)
            let p = CGPoint(x: x(t), y: y)
            travelled += abs(Double(p.x - points[points.count - 1].x))
            points.append(p)
        }
        points.reverse()
        var runs: [EdgePath.Run] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let dx: CGFloat = b.x >= a.x ? 1 : -1
            runs.append(EdgePath.Run(from: a, to: b, tangent: CGVector(dx: dx, dy: 0), normal: CGVector(dx: 0, dy: -1)))
        }
        return EdgePath(runs: runs)
    }

    /// The edge from `from` to `to` (distances along it) as short runs.
    private func path(along sample: (Double) -> EdgePath.Sample, from: Double, to: Double) -> EdgePath {
        guard to > from else { return EdgePath(runs: []) }
        let steps = max(2, Int((to - from) / 3))
        var runs: [EdgePath.Run] = []
        var previous = sample(from)
        for i in 1...steps {
            let next = sample(from + (to - from) * Double(i) / Double(steps))
            runs.append(EdgePath.Run(from: previous.point, to: next.point, tangent: next.tangent, normal: next.normal))
            previous = next
        }
        return EdgePath(runs: runs)
    }
}
#endif
