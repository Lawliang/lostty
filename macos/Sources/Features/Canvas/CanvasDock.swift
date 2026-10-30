#if os(macOS)
import AppKit
import SwiftUI

/// The dock at the bottom of the canvas, centered and over the cards:
/// Lostty's apps as icons on the + menu's glass, laid out like macOS 26's Dock.
/// For now Settings and Usage.
final class CanvasDockView: NSHostingView<CanvasDock> {
    /// Room round the shelf for its shadow.
    nonisolated static let shadowRoom: CGFloat = 16
    /// From the canvas's bottom edge to the shelf.
    nonisolated static let margin: CGFloat = 6
    /// Room above the shelf for the icons' names and an icon dragged off.
    /// Clicks there go through to the canvas.
    nonisolated static let above: CGFloat = 160

    /// The dock's frame of `size` (with the room for its shadow) in
    /// `bounds` (y up): centered, `margin` up from the bottom.
    nonisolated static func frame(size: CGSize, in bounds: CGRect) -> CGRect {
        CGRect(
            x: (bounds.midX - size.width / 2).rounded(), y: bounds.minY + margin - shadowRoom,
            width: size.width, height: size.height)
    }

    /// The shelf itself, without the room for its shadow or above it.
    private var live: CGRect {
        var live = bounds.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom)
        live.size.height -= Self.above
        if isFlipped { live.origin.y += Self.above }
        return live
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        live.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    /// Whether a click at `point` (in the window) is the dock's.
    func covers(_ point: NSPoint) -> Bool {
        !isHiddenOrHasHiddenAncestor && live.contains(convert(point, from: nil))
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        HStack(spacing: 0) {
            ForEach(order, id: \.self) { app in
                CanvasDockIcon(
                    app: app, lifted: lifted == app, label: label(app), action: { open(app) })
                    .popover(isPresented: app == .usage ? $showingUsage : .constant(false), arrowEdge: .top) {
                        TimelineView(.everyMinute) { _ in
                            ClaudeUsageDetails(usage: .shared, accent: .accentColor) { showingUsage = false }
                        }
                    }
                    .offset(lifted == app ? liftOffset : .zero)
                    .frame(width: lifted == app && liftedOff ? 0 : Self.pitch)
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
        .padding(CanvasDockView.shadowRoom)
        .padding(.top, CanvasDockView.above)
    }

    /// The name over an icon: under the pointer, or "Remove" while it's
    /// dragged off. None while another is dragged.
    private func label(_ app: CanvasDockApp) -> String? {
        switch lifted {
        case nil: app.name
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
/// a fine light edge, the symbol flat on it. Under the pointer it grows a
/// little and shows its name above it, as the Dock does; lifted to be
/// dragged it grows more, with a deeper shadow.
struct CanvasDockIcon: View {
    static let size: CGFloat = 44

    let app: CanvasDockApp
    let lifted: Bool
    /// What to show above it, under the pointer or while lifted.
    let label: String?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

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
        .overlay(alignment: .top) {
            if let label, hovered || lifted {
                CanvasDockLabel(text: label)
                    .fixedSize()
                    .alignmentGuide(.top) { $0[.bottom] + 10 }
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.25), value: hovered)
        .animation(.easeOut(duration: 0.15), value: label)
        .onHover { hovered = $0 }
        .accessibilityElement()
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }

    private var scale: CGFloat {
        if reduceMotion { return 1 }
        if lifted { return 1.15 }
        return hovered ? 1.08 : 1
    }
}

/// The name over a dock icon, as the Dock shows one: small text on a
/// dark rounded tag.
private struct CanvasDockLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.7)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }
}
#endif
