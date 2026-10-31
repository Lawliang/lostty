#if os(macOS)
import AppKit
import SwiftUI

/// Whether the dock is out: the pointer is where it sits full size, or D
/// brought it out (and D puts it away). And where along it the pointer
/// is, which its icons grow toward.
final class CanvasDockState: ObservableObject {
    @Published var near = false
    @Published var shown = false
    /// The pointer's x in the dock's view, while it's over the dock.
    @Published var pointerX: CGFloat?
}

/// The dock at the bottom of the canvas, centered and over the cards:
/// Lostty's apps as icons on the + menu's glass, laid out like macOS 26's Dock.
/// For now Settings and Usage. Out of the way it's a miniature of itself,
/// as far from the bottom edge; the pointer where it sits full size, or D,
/// brings it out.
final class CanvasDockView: NSHostingView<CanvasDock> {
    /// Room round the shelf for its shadow.
    nonisolated static let shadowRoom: CGFloat = 16
    /// From the canvas's bottom edge to the shelf.
    nonisolated static let margin: CGFloat = 6
    /// Room above the shelf for the icons' names and an icon dragged off.
    /// Clicks there go through to the canvas.
    nonisolated static let above: CGFloat = 160
    /// Room each side of the shelf for it to widen as its icons grow.
    nonisolated static let sideRoom: CGFloat = 40
    /// How far grown icons stand above the shelf, which is still the dock's.
    nonisolated static let grownRoom = CanvasDockIcon.size * (CanvasDock.magnified - 1)

    private let state: CanvasDockState
    private var nearArea: NSTrackingArea?

    init(state: CanvasDockState) {
        self.state = state
        super.init(rootView: CanvasDock(state: state))
    }

    @available(*, unavailable)
    required init(rootView: CanvasDock) { fatalError("init(rootView:) is not supported") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The dock's frame of `size` (with the room for its shadow) in
    /// `bounds` (y up): centered, `margin` up from the bottom.
    nonisolated static func frame(size: CGSize, in bounds: CGRect) -> CGRect {
        CGRect(
            x: (bounds.midX - size.width / 2).rounded(), y: bounds.minY + margin - shadowRoom,
            width: size.width, height: size.height)
    }

    /// The shelf full size and its grown icons, without the room for its
    /// shadow, beside it or above them: where the pointer brings it out and
    /// grows its icons, and its clicks land.
    private var live: CGRect {
        var live = bounds.insetBy(dx: Self.shadowRoom + Self.sideRoom, dy: Self.shadowRoom)
        live.size.height -= Self.above - Self.grownRoom
        if isFlipped { live.origin.y += Self.above - Self.grownRoom }
        return live
    }

    /// Its size follows its icons (one dragged off or put back): the canvas
    /// lays it out again.
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        live.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    /// Whether a click at `point` (in the window) is the dock's.
    func covers(_ point: NSPoint) -> Bool {
        !isHiddenOrHasHiddenAncestor && live.contains(convert(point, from: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let nearArea { removeTrackingArea(nearArea) }
        let area = NSTrackingArea(
            rect: live, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp], owner: self)
        addTrackingArea(area)
        nearArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === nearArea { state.near = true }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard event.trackingArea === nearArea else { return }
        state.near = false
        state.pointerX = nil
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        point(at: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        point(at: event)
    }

    private func point(at event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        state.pointerX = live.contains(point) ? point.x : nil
    }
}

/// The dock's apps.
enum CanvasDockApp: String, CaseIterable {
    case settings, usage

    /// Where the order the owner dragged them into is kept, and the apps
    /// dragged off.
    static let orderKey = "LosttyDockOrder"
    static let removedKey = "LosttyDockRemoved"

    var name: String {
        switch self {
        case .settings: "Settings"
        case .usage: "Usage"
        }
    }

    var symbol: String {
        switch self {
        case .settings: "gearshape.fill"
        case .usage: "gauge.with.dots.needle.67percent"
        }
    }

    /// The icon's color at its top, then at its bottom.
    var colors: [Color] {
        switch self {
        case .settings: [Color(white: 0.78), Color(white: 0.5)]
        case .usage: [Color(red: 0.2, green: 0.78, blue: 0.7), Color(red: 0.0, green: 0.5, blue: 0.56)]
        }
    }

    var glyph: Color {
        switch self {
        case .settings: Color(white: 0.94)
        case .usage: .white
        }
    }

    /// Names, comma-separated, as apps: names it doesn't know and repeats
    /// dropped.
    static func apps(_ saved: String) -> [Self] {
        var apps: [Self] = []
        for app in saved.split(separator: ",").compactMap({ Self(rawValue: String($0)) }) where !apps.contains(app) {
            apps.append(app)
        }
        return apps
    }

    static func saved(_ apps: [Self]) -> String {
        apps.map(\.rawValue).joined(separator: ",")
    }

    /// The dock's apps: `saved`'s order, apps it's missing at the end,
    /// without the `removed` ones.
    static func order(from saved: String, removed: String) -> [Self] {
        let order = apps(saved)
        let gone = apps(removed)
        return (order + allCases.filter { !order.contains($0) }).filter { !gone.contains($0) }
    }

    /// `order` with `app` taken out and put back at `slot`.
    static func moving(_ app: Self, to slot: Int, in order: [Self]) -> [Self] {
        var moved = order.filter { $0 != app }
        moved.insert(app, at: min(max(slot, 0), moved.count))
        return moved
    }
}

struct CanvasDock: View {
    /// Round the icons: about two fifths of an icon each side and between,
    /// a little less above and below. Half the space between is each
    /// icon's own, so an icon dragged off takes its share with it.
    static let inset = EdgeInsets(top: 16, leading: 9, bottom: 16, trailing: 9)
    static let spacing: CGFloat = 18
    static let pitch = CanvasDockIcon.size + spacing
    /// How long an icon is held before it lifts and can be dragged.
    static let hold: Duration = .milliseconds(350)
    /// Further than this before the hold is up, and it's no click or drag.
    static let slop: CGFloat = 4
    /// Dragged this far up, the icon is off the dock: dropped, it's removed.
    static let off: CGFloat = 100
    static let move = Animation.spring(response: 0.3, dampingFraction: 0.8)
    /// The dock's size out of the way.
    static let mini: CGFloat = 0.4
    /// As the Dock magnifies: the icon under the pointer grows this much,
    /// and its neighbors less the further they are, out to `reach`.
    static let magnified: CGFloat = 1.35
    static let reach = 3 * pitch

    @ObservedObject var state: CanvasDockState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CanvasDockApp.orderKey, store: .ghostty) private var savedOrder = ""
    @AppStorage(CanvasDockApp.removedKey, store: .ghostty) private var removed = ""
    @State private var showingUsage = false
    @State private var hovering = false
    /// The icon under a held mouse button, and whether it went past `slop`
    /// before lifting.
    @State private var pressed: CanvasDockApp?
    @State private var slipped = false
    /// The icon being dragged, the order it started from, the order the
    /// others have moved into round it, and whether it's off the dock.
    @State private var lifted: CanvasDockApp?
    @State private var startOrder: [CanvasDockApp] = []
    @State private var arranging: [CanvasDockApp]?
    @State private var liftedOff = false
    /// The lifted icon's offset from its place, so it stays under the pointer.
    @State private var liftOffset: CGSize = .zero

    private var order: [CanvasDockApp] { arranging ?? CanvasDockApp.order(from: savedOrder, removed: removed) }

    /// Out, and while an icon is held or Usage is open, though the pointer
    /// has left.
    private var out: Bool { state.near || state.shown || pressed != nil || lifted != nil || showingUsage }

    /// The icons' places at rest, from the dock view's left edge.
    private var firstSlot: CGFloat { CanvasDockView.shadowRoom + CanvasDockView.sideRoom + Self.inset.leading }

    /// How much the icon in `slot` grows, by how far its place at rest is
    /// from the pointer. None while an icon is dragged.
    private func growth(_ slot: Int) -> CGFloat {
        guard out, lifted == nil, !reduceMotion, let x = state.pointerX else { return 1 }
        let center = firstSlot + (CGFloat(slot) + 0.5) * Self.pitch
        return CanvasDock.growth(distance: abs(x - center))
    }

    /// The Dock's falloff: full at the pointer, easing to none at `reach`.
    static func growth(distance: CGFloat) -> CGFloat {
        guard distance < reach else { return 1 }
        return 1 + (magnified - 1) * (1 + cos(.pi * distance / reach)) / 2
    }

    /// The icon whose place at rest is under the pointer.
    private var pointedSlot: Int? {
        guard let x = state.pointerX else { return nil }
        let slot = Int(((x - firstSlot) / Self.pitch).rounded(.down))
        return order.indices.contains(slot) ? slot : nil
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        let restWidth = CGFloat(order.count) * Self.pitch + Self.inset.leading + Self.inset.trailing
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.element) { slot, app in
                let grown = growth(slot)
                CanvasDockIcon(
                    app: app, lifted: lifted == app, grown: grown, label: label(app, slot), action: { open(app) })
                    .popover(isPresented: app == .usage ? $showingUsage : .constant(false), arrowEdge: .top) {
                        TimelineView(.everyMinute) { _ in
                            ClaudeUsageDetails(usage: .shared, accent: .accentColor) { showingUsage = false }
                        }
                    }
                    .offset(lifted == app ? liftOffset : .zero)
                    .frame(width: lifted == app && liftedOff ? 0 : Self.pitch + CanvasDockIcon.size * (grown - 1))
                    .zIndex(lifted == app ? 1 : 0)
                    .gesture(press(app))
            }
        }
        .padding(Self.inset)
        // The + menu's glass without its prism, its rim lit the same way
        // while the pointer is over it.
        .modifier(CanvasAddLitGlass(shape: shape, dark: scheme == .dark, lit: hovering,
                                    interactive: false, reduceMotion: reduceMotion, prism: false))
        .onHover { inside in withAnimation(CanvasAddButton.light) { hovering = inside } }
        .contextMenu {
            ForEach(CanvasDockApp.apps(removed), id: \.self) { app in
                Button("Add \(app.name) to Dock") { putBack(app) }
            }
        }
        .scaleEffect(out ? 1 : Self.mini, anchor: .bottom)
        .allowsHitTesting(out)
        .animation(reduceMotion ? nil : Self.move, value: out)
        .animation(.easeOut(duration: 0.12), value: state.pointerX == nil)
        .frame(width: restWidth + 2 * CanvasDockView.sideRoom)
        .padding(CanvasDockView.shadowRoom)
        .padding(.top, CanvasDockView.above)
    }

    /// The name over an icon: under the pointer, or "Remove" while it's
    /// dragged off. None while another is dragged.
    private func label(_ app: CanvasDockApp, _ slot: Int) -> String? {
        switch lifted {
        case nil: out && pointedSlot == slot ? app.name : nil
        case app: liftedOff ? "Remove" : nil
        default: nil
        }
    }

    private func open(_ app: CanvasDockApp) {
        switch app {
        case .settings: SettingsUI.show()
        case .usage: showingUsage.toggle()
        }
    }

    /// As on the iPhone: a click opens the app; held still for `hold`, the
    /// icon lifts and drags along the dock, the others making room, or off
    /// it to remove it.
    private func press(_ app: CanvasDockApp) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if pressed == nil {
                    pressed = app
                    slipped = false
                    Task { @MainActor in
                        try? await Task.sleep(for: Self.hold)
                        guard pressed == app, !slipped else { return }
                        withAnimation(Self.move) {
                            lifted = app
                            startOrder = order
                            arranging = order
                        }
                    }
                }
                if lifted == app {
                    drag(app, by: value.translation)
                } else if hypot(value.translation.width, value.translation.height) > Self.slop {
                    slipped = true
                }
            }
            .onEnded { _ in
                defer { pressed = nil }
                if lifted == app {
                    drop(app)
                } else if !slipped {
                    open(app)
                }
            }
    }

    private func drag(_ app: CanvasDockApp, by translation: CGSize) {
        guard let start = startOrder.firstIndex(of: app) else { return }
        // Along the dock, from its first slot to its last; up, as far as
        // the room above it. The last app can't come off.
        let along = min(max(translation.width, -CGFloat(start) * Self.pitch),
                        CGFloat(startOrder.count - 1 - start) * Self.pitch)
        let up = min(max(translation.height, -(CanvasDockView.above - 20)), 10)
        let off = -up > Self.off && startOrder.count > 1
        // Off the dock it keeps its place, which closes up.
        let moved = off ? (arranging ?? startOrder)
            : CanvasDockApp.moving(app, to: start + Int((along / Self.pitch).rounded()), in: startOrder)
        let index = CGFloat(moved.firstIndex(of: app) ?? start)
        let center = off ? index * Self.pitch : (index + 0.5) * Self.pitch
        let offset = CGSize(width: (CGFloat(start) + 0.5) * Self.pitch + along - center, height: up)
        if moved == arranging && off == liftedOff {
            liftOffset = offset
        } else {
            // One animation for all: the icon's place and its offset move
            // the same distance opposite ways, so it stays under the pointer.
            withAnimation(Self.move) {
                arranging = moved
                liftedOff = off
                liftOffset = offset
            }
        }
    }

    private func drop(_ app: CanvasDockApp) {
        withAnimation(Self.move) {
            if let arranging {
                savedOrder = CanvasDockApp.saved(arranging)
                if liftedOff { removed = CanvasDockApp.saved(CanvasDockApp.apps(removed) + [app]) }
            }
            arranging = nil
            lifted = nil
            liftedOff = false
            liftOffset = .zero
        }
    }

    private func putBack(_ app: CanvasDockApp) {
        withAnimation(Self.move) {
            removed = CanvasDockApp.saved(CanvasDockApp.apps(removed).filter { $0 != app })
            savedOrder = CanvasDockApp.saved(CanvasDockApp.apps(savedOrder).filter { $0 != app } + [app])
        }
    }
}

/// An app's icon, as macOS 26 draws one: a squircle of soft gradient with
/// a fine light edge, the symbol flat on it. It grows up from the shelf by
/// `grown` as the pointer nears, and lifted to be dragged it grows more,
/// with a deeper shadow. Its name shows in a bubble above it.
struct CanvasDockIcon: View {
    static let size: CGFloat = 44

    let app: CanvasDockApp
    let lifted: Bool
    let grown: CGFloat
    /// What to show above it: its name under the pointer, or "Remove".
    let label: String?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.size * 0.24, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: app.colors, startPoint: .top, endPoint: .bottom))
            Image(systemName: app.symbol)
                .font(.system(size: Self.size * 0.56, weight: .regular))
                .foregroundStyle(app.glyph)
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.5), .white.opacity(0.12), .white.opacity(0.25)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75)
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(shape)
        .shadow(color: .black.opacity(lifted ? 0.35 : 0.18), radius: lifted ? 8 : 1.5, y: lifted ? 4 : 1)
        .scaleEffect(scale, anchor: .bottom)
        // Always there, faded out: a label in an `if` loses its alignment
        // guide and lands on the icon.
        .overlay(alignment: .top) {
            CanvasDockLabel(text: label ?? app.name, tail: .bottom)
                .fixedSize()
                // Clear of the icon at its grown size.
                .alignmentGuide(.top) { $0[.bottom] + 6 + Self.size * (scale - 1) }
                .opacity(label == nil ? 0 : 1)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.12), value: label)
        .accessibilityElement()
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        return lifted ? 1.15 : grown
    }
}

/// The name over a dock icon, as the Dock shows one, in the dock's and the
/// + menu's glass and rim: a bubble whose tail points at what it names
/// (down to a dock icon; right, to a + menu item, with its key).
struct CanvasDockLabel: View {
    let text: String
    var key: String?
    let tail: CanvasLabelBubble.Tail

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        let ink = dark ? Color.white : Color.black
        HStack(spacing: 6) {
            Text(text)
            if let key {
                Text(key.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.8))
                    .frame(minWidth: 16, minHeight: 16)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ink.opacity(0.14)))
            }
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(ink)
        .padding(.leading, 10)
        .padding(.trailing, key == nil ? 10 : 5)
        .padding(.vertical, 5)
        // Room for the tail, outside the text.
        .padding(tail == .bottom ? .bottom : .trailing, CanvasLabelBubble.tailLength)
        .modifier(CanvasAddLitGlass(shape: CanvasLabelBubble(tail: tail), dark: dark, lit: false,
                                    interactive: false, reduceMotion: reduceMotion, prism: false))
    }
}

/// A rounded bubble with a tail centered on one edge, its outline one path
/// so the glass and the rim go round the tail too.
struct CanvasLabelBubble: InsettableShape {
    enum Tail { case bottom, trailing }

    static let tailLength: CGFloat = 6
    static let tailWidth: CGFloat = 12
    static let radius: CGFloat = 9

    let tail: Tail
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        var body = rect
        if tail == .bottom { body.size.height -= Self.tailLength } else { body.size.width -= Self.tailLength }
        let radius = min(Self.radius, body.height / 2, body.width / 2)
        let half = Self.tailWidth / 2
        return Path { path in
            path.move(to: CGPoint(x: body.midX, y: body.minY))
            path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                        tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: radius)
            if tail == .trailing {
                path.addLine(to: CGPoint(x: body.maxX, y: body.midY - half))
                path.addLine(to: CGPoint(x: rect.maxX, y: body.midY))
                path.addLine(to: CGPoint(x: body.maxX, y: body.midY + half))
            }
            path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                        tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: radius)
            if tail == .bottom {
                path.addLine(to: CGPoint(x: body.midX + half, y: body.maxY))
                path.addLine(to: CGPoint(x: body.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: body.midX - half, y: body.maxY))
            }
            path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                        tangent2End: CGPoint(x: body.minX, y: body.minY), radius: radius)
            path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                        tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: radius)
            path.closeSubpath()
        }
    }

    func inset(by amount: CGFloat) -> Self {
        var bubble = self
        bubble.inset += amount
        return bubble
    }
}
#endif
