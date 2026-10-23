#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// The canvas's + button, at the bottom right over the cards and the same
/// size at every zoom. Clicking it opens a pill of what it can add above
/// it; choosing one, clicking anywhere else or Escape closes it.
final class CanvasAddMenuView: NSView {
    enum Item: CaseIterable {
        case terminal, ticket

        var title: String {
            switch self {
            case .terminal: "New Terminal"
            case .ticket: "New Ticket"
            }
        }

        var symbol: String {
            switch self {
            case .terminal: "terminal"
            case .ticket: "ticket"
            }
        }
    }

    /// The button's diameter; the pill is as wide.
    static let diameter: CGFloat = 44
    /// From the canvas's bottom and right edges to the button's.
    static let margin: CGFloat = 20
    /// Room round the button and pill for their shadows.
    static let shadowRoom: CGFloat = 16
    static let itemSize: CGFloat = 36
    static let pillPadding: CGFloat = 4
    static let pillGap: CGFloat = 10

    static var pillHeight: CGFloat {
        let count = CGFloat(Item.allCases.count)
        return count * itemSize + (count - 1) * pillPadding + 2 * pillPadding
    }

    /// Big enough for the pill open above the button.
    static var size: CGSize {
        CGSize(width: diameter + 2 * shadowRoom, height: pillHeight + pillGap + diameter + 2 * shadowRoom)
    }

    var chose: ((Item) -> Void)?
    private let state = CanvasAddMenuState()
    private lazy var host = NSHostingView(rootView: CanvasAddButton(state: state) { [weak self] item in
        self?.close()
        self?.chose?(item)
    })
    private var monitor: Any?
    private var opened: AnyCancellable?

    init() {
        super.init(frame: .zero)
        addSubview(host)
        opened = state.$isOpen.dropFirst().sink { [weak self] isOpen in self?.watchOutside(isOpen) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        host.frame = bounds
    }

    /// The button, and the pill while it's open (y up): clicks anywhere else
    /// in the view go on to the cards under it.
    private var live: CGRect {
        let inset = bounds.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom)
        guard !state.isOpen else { return inset }
        return CGRect(x: inset.minX, y: inset.minY, width: Self.diameter, height: Self.diameter)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        live.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    /// Whether a click at `point` (in the window) is the menu's.
    func covers(_ point: NSPoint) -> Bool {
        !isHiddenOrHasHiddenAncestor && live.contains(convert(point, from: nil))
    }

    /// While the pill is open, a click anywhere else or Escape closes it
    /// (the click still lands; Escape goes no further).
    private func watchOutside(_ isOpen: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isOpen else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, event.window === window else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event }
                close()
                return nil
            }
            if !covers(event.locationInWindow) { close() }
            return event
        }
    }

    private func close() {
        withAnimation(CanvasAddButton.spring) { state.isOpen = false }
    }
}

final class CanvasAddMenuState: ObservableObject {
    @Published var isOpen = false
}

/// The + button, after Apple Music's 2026 icon: a clear disc of Liquid
/// Glass with a bright rim, light splitting into color at two opposite
/// edges, and a monochrome glyph (black in light, white and glowing in
/// dark). The light turns as the pointer comes near; a click sends ripples
/// out, as the icon was shaped by ripples in oil. It turns to × while the
/// pill of what it adds is open above it, a capsule of the same glass.
struct CanvasAddButton: View {
    @ObservedObject var state: CanvasAddMenuState
    let choose: (CanvasAddMenuView.Item) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var pillHovering = false
    @State private var ripples = 0

    static let spring = Animation.spring(response: 0.28, dampingFraction: 0.8)
    /// How the light turns and the rim brightens as the pointer comes near.
    static let light = Animation.spring(response: 0.6, dampingFraction: 0.75)

    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: CanvasAddMenuView.pillGap) {
            if state.isOpen {
                pill.transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
            Button {
                withAnimation(Self.spring) { state.isOpen.toggle() }
                if !reduceMotion { ripples += 1 }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(dark ? Color.white : Color.black)
                    .shadow(color: .white.opacity(dark ? 0.55 : 0), radius: 5)
                    .rotationEffect(.degrees(state.isOpen ? 45 : 0))
                    .frame(width: CanvasAddMenuView.diameter, height: CanvasAddMenuView.diameter)
                    .modifier(CanvasAddLitGlass(shape: Circle(), dark: dark, lit: hovering,
                                                interactive: true, reduceMotion: reduceMotion))
                    .background(CanvasAddRipple(trigger: ripples, dark: dark))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { inside in withAnimation(Self.light) { hovering = inside } }
            .help(state.isOpen ? "Close" : "Add to Canvas")
            .accessibilityLabel(state.isOpen ? "Close" : "Add to Canvas")
        }
        .padding(CanvasAddMenuView.shadowRoom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// The same glass as the button, as a capsule: its light turns while
    /// the pointer is over it, but it has no press feedback of its own,
    /// since its icons are the buttons.
    private var pill: some View {
        VStack(spacing: CanvasAddMenuView.pillPadding) {
            ForEach(CanvasAddMenuView.Item.allCases, id: \.self) { item in
                CanvasAddItem(item: item, dark: dark) { choose(item) }
            }
        }
        .padding(CanvasAddMenuView.pillPadding)
        .modifier(CanvasAddLitGlass(shape: Capsule(), dark: dark, lit: pillHovering,
                                    interactive: false, reduceMotion: reduceMotion))
        .onHover { inside in withAnimation(Self.light) { pillHovering = inside } }
    }
}

/// Glass in `shape` with its rim and prism, lit while the pointer is over
/// it. The merge countdown (CanvasDrop) is it too, without the prism.
struct CanvasAddLitGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let dark: Bool
    let lit: Bool
    let interactive: Bool
    let reduceMotion: Bool
    var prism = true

    func body(content: Content) -> some View {
        content
            .modifier(CanvasAddGlass(shape: shape, dark: dark, interactive: interactive))
            .overlay {
                if prism {
                    CanvasAddPrism(shape: shape, dark: dark, turn: .degrees(lit && !reduceMotion ? 38 : 0))
                        .opacity(lit ? 1 : 0.85)
                }
            }
            .overlay(CanvasAddRim(shape: shape, dark: dark, lit: lit))
    }
}

/// The glass's body: Liquid Glass on macOS 26, which bends the cards
/// behind it and casts its own shadow; before that, the thinnest
/// material with one.
private struct CanvasAddGlass<S: Shape>: ViewModifier {
    let shape: S
    let dark: Bool
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                .regular.tint(dark ? .black.opacity(0.35) : .white.opacity(0.35)).interactive(interactive),
                in: shape)
        } else {
            content.background(
                shape.fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: 10, y: 4))
        }
    }
}

/// The glass's edge: brightest at the top left, where the light falls.
private struct CanvasAddRim<S: InsettableShape>: View {
    let shape: S
    let dark: Bool
    let lit: Bool

    var body: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [.white.opacity(lit ? 0.95 : 0.8), .white.opacity(dark ? 0.08 : 0.25),
                         .white.opacity(dark ? 0.35 : 0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 0.8)
        .allowsHitTesting(false)
    }
}

/// Light split by the glass's edge into color, as on Apple Music's icon: an
/// arc at the top right and one at the bottom left, cyan into blue with a
/// warm fringe. Brighter on dark glass, where it adds light. The arcs are
/// stops of one gradient round the center, so they hug any shape's edge,
/// and turning the gradient moves the light without turning the shape.
private struct CanvasAddPrism<S: InsettableShape>: View {
    let shape: S
    let dark: Bool
    let turn: Angle

    var body: some View {
        let gradient = AngularGradient(stops: Self.stops, center: .center,
                                       startAngle: turn, endAngle: turn + .degrees(360))
        ZStack {
            // A soft bloom under a sharp line.
            shape.inset(by: 2)
                .stroke(gradient, lineWidth: 4)
                .blur(radius: 2.5)
                .opacity(dark ? 0.9 : 0.6)
            shape.inset(by: 2)
                .stroke(gradient, lineWidth: 2.2)
        }
        .blendMode(dark ? .plusLighter : .normal)
        .allowsHitTesting(false)
    }

    /// Clear but for the two arcs. The gradient runs clockwise from the
    /// right: 0.75 is the top.
    private static var stops: [Gradient.Stop] {
        let indigo = Color(red: 0.35, green: 0.25, blue: 0.95)
        let ember = Color(red: 1, green: 0.45, blue: 0.2)
        return arc(from: 0.27, to: 0.49, [.clear, ember, .white, .cyan, .blue, .clear])
            + arc(from: 0.77, to: 0.99, [.clear, .white, .cyan, .blue, indigo, .clear])
    }

    private static func arc(from: Double, to: Double, _ colors: [Color]) -> [Gradient.Stop] {
        colors.enumerated().map { index, color in
            Gradient.Stop(color: color, location: from + (to - from) * Double(index) / Double(colors.count - 1))
        }
    }
}

/// Two rings that spread from the disc and fade on each click, like the
/// ripples in oil Apple Music's icon was shaped by.
private struct CanvasAddRipple: View {
    let trigger: Int
    let dark: Bool

    private struct Ring {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    var body: some View {
        ZStack {
            ring(delay: 0)
            ring(delay: 0.14)
        }
        .allowsHitTesting(false)
    }

    private func ring(delay: TimeInterval) -> some View {
        Circle()
            .stroke(Color.primary.opacity(dark ? 0.5 : 0.35), lineWidth: 1.2)
            .keyframeAnimator(initialValue: Ring(), trigger: trigger) { ring, value in
                ring.scaleEffect(value.scale).opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: delay)
                    CubicKeyframe(1.36, duration: 0.75)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: delay)
                    MoveKeyframe(1)
                    LinearKeyframe(0, duration: 0.75)
                }
            }
    }
}

/// One of the pill's icons, monochrome like the + (black in light, white
/// and glowing in dark), lit while the pointer is over it.
private struct CanvasAddItem: View {
    let item: CanvasAddMenuView.Item
    let dark: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(dark ? Color.white : Color.black)
                .shadow(color: .white.opacity(dark ? 0.45 : 0), radius: 4)
                .frame(width: CanvasAddMenuView.itemSize, height: CanvasAddMenuView.itemSize)
                .background(Color.primary.opacity(hovering ? 0.1 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.title)
        .accessibilityLabel(item.title)
    }
}
#endif
