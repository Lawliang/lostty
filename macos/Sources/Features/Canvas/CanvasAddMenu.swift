#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// The canvas's + button, at the bottom right over the cards and the same
/// size at every zoom. Clicking it opens a pill of what it can add above
/// it, each named on its left with its key under the pointer; choosing
/// one, clicking anywhere else or Escape closes it. New Agent opens a
/// list of agents (AgentRecipe) to the pill's left instead.
final class CanvasAddMenuView: NSView {
    enum Item: CaseIterable {
        case terminal, agent, zone

        var title: String {
            switch self {
            case .terminal: "New Terminal"
            case .agent: "New Agent"
            case .zone: "New Zone"
            }
        }

        var symbol: String {
            switch self {
            case .terminal: "terminal"
            case .agent: "person.2"
            case .zone: "square.dashed"
            }
        }

        /// Its key on the canvas while nothing has the keyboard.
        var key: String {
            switch self {
            case .terminal: "t"
            case .agent: "a"
            case .zone: "z"
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
    /// Room left of the pill for its items' names, and the agents list.
    static let labelRoom: CGFloat = 170
    static let agentRowHeight: CGFloat = 30
    static let agentListWidth: CGFloat = 156
    /// The agents list shows this many rows; more scroll.
    static let agentRowsShown = 6

    static var pillHeight: CGFloat {
        let count = CGFloat(Item.allCases.count)
        return count * itemSize + (count - 1) * pillPadding + 2 * pillPadding
    }

    static func agentListHeight(rows: Int) -> CGFloat {
        let count = CGFloat(min(max(rows, 1), agentRowsShown))
        return count * agentRowHeight + (count - 1) * pillPadding + 2 * pillPadding
    }

    /// Big enough for the pill open above the button, and the agents list
    /// beside it.
    static var size: CGSize {
        let column = max(pillHeight, agentListHeight(rows: agentRowsShown))
        return CGSize(width: labelRoom + diameter + 2 * shadowRoom, height: column + pillGap + diameter + 2 * shadowRoom)
    }

    var chose: ((Item) -> Void)?
    var choseAgent: ((AgentRecipe) -> Void)?
    private let state = CanvasAddMenuState()
    private lazy var host = NSHostingView(rootView: CanvasAddButton(state: state, choose: { [weak self] item in
        self?.close()
        self?.chose?(item)
    }, chooseAgent: { [weak self] recipe in
        self?.close()
        self?.choseAgent?(recipe)
    }))
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

    /// The button, the pill while it's open and the agents list while
    /// that is (y up): clicks anywhere else in the view, its items' names
    /// too, go on to the cards under it.
    private var live: CGRect {
        let inset = bounds.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom)
        let column = CGRect(x: inset.maxX - Self.diameter, y: inset.minY, width: Self.diameter, height: inset.height)
        if state.agentsOpen { return inset }
        guard !state.isOpen else { return column }
        return CGRect(x: column.minX, y: inset.minY, width: Self.diameter, height: Self.diameter)
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
        withAnimation(CanvasAddButton.spring) {
            state.isOpen = false
            state.agentsOpen = false
        }
    }

    /// The A key: the pill opens with its agents list out.
    func openAgents() {
        state.agents = AgentRecipe.all()
        withAnimation(CanvasAddButton.spring) {
            state.isOpen = true
            state.agentsOpen = true
        }
    }
}

final class CanvasAddMenuState: ObservableObject {
    @Published var isOpen = false
    @Published var agentsOpen = false
    /// Read from their files each time the list opens.
    @Published var agents: [AgentRecipe] = []
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
    let chooseAgent: (AgentRecipe) -> Void
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
        VStack(alignment: .trailing, spacing: CanvasAddMenuView.pillGap) {
            if state.isOpen {
                // New Agent is the pill's middle item: the list opens level
                // with it and grows out of its side.
                HStack(alignment: .center, spacing: CanvasAddMenuView.pillGap) {
                    if state.agentsOpen {
                        agentList.transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
                    }
                    pill
                }
                .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
            Button {
                withAnimation(Self.spring) {
                    state.isOpen.toggle()
                    state.agentsOpen = false
                }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    /// The button's glass as a capsule, without its prism: its rim lights
    /// while the pointer is over it, but it has no press feedback of its
    /// own, since its icons are the buttons.
    private var pill: some View {
        VStack(spacing: CanvasAddMenuView.pillPadding) {
            ForEach(CanvasAddMenuView.Item.allCases, id: \.self) { item in
                CanvasAddItem(item: item, dark: dark, isOn: item == .agent && state.agentsOpen,
                              showsLabel: !state.agentsOpen) { pick(item) }
            }
        }
        .padding(CanvasAddMenuView.pillPadding)
        .modifier(CanvasAddLitGlass(shape: Capsule(), dark: dark, lit: pillHovering,
                                    interactive: false, reduceMotion: reduceMotion, prism: false))
        .onHover { inside in withAnimation(Self.light) { pillHovering = inside } }
    }

    /// New Agent opens or closes the agents list; the rest add.
    private func pick(_ item: CanvasAddMenuView.Item) {
        guard item == .agent else { return choose(item) }
        if !state.agentsOpen { state.agents = AgentRecipe.all() }
        withAnimation(Self.spring) { state.agentsOpen.toggle() }
    }

    /// The agents New Agent opens, each its icon and name, in the pill's
    /// glass.
    private var agentList: some View {
        let rows = VStack(spacing: CanvasAddMenuView.pillPadding) {
            ForEach(state.agents) { recipe in
                CanvasAgentRow(recipe: recipe, dark: dark) { chooseAgent(recipe) }
            }
        }
        .padding(CanvasAddMenuView.pillPadding)
        return ScrollView(.vertical) { rows }
            .scrollDisabled(state.agents.count <= CanvasAddMenuView.agentRowsShown)
            .frame(width: CanvasAddMenuView.agentListWidth,
                   height: CanvasAddMenuView.agentListHeight(rows: state.agents.count))
            .modifier(CanvasAddLitGlass(shape: RoundedRectangle(cornerRadius: 19, style: .continuous), dark: dark,
                                        lit: false, interactive: false, reduceMotion: reduceMotion, prism: false))
    }
}

/// One agent in New Agent's list: lit while the pointer is over it.
private struct CanvasAgentRow: View {
    let recipe: AgentRecipe
    let dark: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: recipe.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                Text(recipe.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(dark ? Color.white : Color.black)
            .padding(.horizontal, 10)
            .frame(height: CanvasAddMenuView.agentRowHeight)
            .background(Color.primary.opacity(hovering ? 0.1 : 0), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(recipe.instructions.split(whereSeparator: \.isNewline).first.map(String.init) ?? recipe.name)
        .accessibilityLabel("New \(recipe.name)")
    }
}

/// Glass in `shape` with its rim and prism, lit while the pointer is over
/// it. The + menu, the merge countdown (CanvasDrop) and the dock
/// (CanvasDock) are it too, without the prism.
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

/// The glass's body: Liquid Glass on macOS 26, the clear kind, lightly
/// tinted, so the terminals behind it stay readable as it bends them, and
/// it casts its own shadow; before that, the thinnest material with one.
private struct CanvasAddGlass<S: Shape>: ViewModifier {
    let shape: S
    let dark: Bool
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                .clear.tint(dark ? .black.opacity(0.12) : .white.opacity(0.12)).interactive(interactive),
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
/// and glowing in dark). While the pointer is over it, it's lit and named
/// on its left with its key, as the dock names its icons.
private struct CanvasAddItem: View {
    let item: CanvasAddMenuView.Item
    let dark: Bool
    /// New Agent while its list is out.
    var isOn = false
    var showsLabel = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(dark ? Color.white : Color.black)
                .shadow(color: .white.opacity(dark ? 0.45 : 0), radius: 4)
                .frame(width: CanvasAddMenuView.itemSize, height: CanvasAddMenuView.itemSize)
                .background(Color.primary.opacity(hovering || isOn ? 0.1 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // Always there, faded out: a label in an `if` loses its alignment
        // guide and lands on the item.
        .overlay(alignment: .leading) {
            CanvasDockLabel(text: item.title, key: item.key, tail: .trailing)
                .fixedSize()
                .alignmentGuide(.leading) { $0[.trailing] + CanvasAddMenuView.pillPadding + 6 }
                .opacity(hovering && showsLabel ? 1 : 0)
                // Gone at once when the agents list opens where it was.
                .transaction { if !showsLabel { $0.animation = nil } }
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(item.title)
    }
}
#endif
