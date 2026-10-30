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
    nonisolated static let margin: CGFloat = 12

    /// The dock's frame of `size` (with the room for its shadow) in
    /// `bounds` (y up): centered, `margin` up from the bottom.
    nonisolated static func frame(size: CGSize, in bounds: CGRect) -> CGRect {
        CGRect(
            x: (bounds.midX - size.width / 2).rounded(), y: bounds.minY + margin - shadowRoom,
            width: size.width, height: size.height)
    }

    /// The shelf itself, without the room for its shadow.
    private var live: CGRect {
        bounds.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        live.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    /// Whether a click at `point` (in the window) is the dock's.
    func covers(_ point: NSPoint) -> Bool {
        !isHiddenOrHasHiddenAncestor && live.contains(convert(point, from: nil))
    }
}

struct CanvasDock: View {
    /// Round the icons: about two fifths of an icon each side and between,
    /// a little less above and below.
    static let inset = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingUsage = false
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        HStack(spacing: 18) {
            CanvasDockIcon(
                name: "Settings", symbol: "gearshape.fill",
                colors: [Color(white: 0.78), Color(white: 0.5)], glyph: Color(white: 0.94)
            ) { SettingsUI.show() }
            CanvasDockIcon(
                name: "Usage", symbol: "gauge.with.dots.needle.67percent",
                colors: [Color(red: 0.2, green: 0.78, blue: 0.7), Color(red: 0.0, green: 0.5, blue: 0.56)],
                glyph: .white
            ) { showingUsage.toggle() }
                .popover(isPresented: $showingUsage, arrowEdge: .top) {
                    TimelineView(.everyMinute) { _ in
                        ClaudeUsageDetails(usage: .shared, accent: .accentColor) { showingUsage = false }
                    }
                }
        }
        .padding(Self.inset)
        // The + menu's glass without its prism, its rim lit the same way
        // while the pointer is over it.
        .modifier(CanvasAddLitGlass(shape: shape, dark: scheme == .dark, lit: hovering,
                                    interactive: false, reduceMotion: reduceMotion, prism: false))
        .onHover { inside in withAnimation(CanvasAddButton.light) { hovering = inside } }
        .padding(CanvasDockView.shadowRoom)
    }
}

/// An app's icon, as macOS 26 draws one: a squircle of soft gradient with
/// a fine light edge, the symbol flat on it. It grows a little under the
/// pointer, and names itself in a tooltip.
struct CanvasDockIcon: View {
    static let size: CGFloat = 44

    let name: String
    let symbol: String
    /// The color at its top, then at its bottom.
    let colors: [Color]
    let glyph: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.size * 0.24, style: .continuous)
        Button(action: action) {
            ZStack {
                shape.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                Image(systemName: symbol)
                    .font(.system(size: Self.size * 0.56, weight: .regular))
                    .foregroundStyle(glyph)
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.12), .white.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            }
            .frame(width: Self.size, height: Self.size)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            .scaleEffect(hovered && !reduceMotion ? 1.08 : 1, anchor: .bottom)
            .animation(.spring(duration: 0.25), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(name)
        .accessibilityLabel(name)
    }
}
#endif
