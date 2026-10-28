#if os(macOS)
import AppKit
import SwiftUI

/// The dock at the bottom of the canvas, centered and over the cards:
/// Lostty's apps as icons on a glass shelf, after iOS 26's dock. For now
/// Settings and Usage.
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
    @Environment(\.colorScheme) private var scheme
    @State private var showingUsage = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        HStack(spacing: 14) {
            CanvasDockIcon(
                name: "Settings", symbol: "gearshape.fill",
                colors: [Color(white: 0.86), Color(white: 0.6)], glyph: Color(white: 0.28)
            ) { SettingsUI.show() }
            CanvasDockIcon(
                name: "Usage", symbol: "gauge.with.dots.needle.67percent",
                colors: [Color(red: 0.32, green: 0.86, blue: 0.68), Color(red: 0.0, green: 0.6, blue: 0.62)],
                glyph: .white
            ) { showingUsage.toggle() }
                .popover(isPresented: $showingUsage, arrowEdge: .top) {
                    TimelineView(.everyMinute) { _ in
                        ClaudeUsageDetails(usage: .shared, accent: .accentColor) { showingUsage = false }
                    }
                }
        }
        .padding(10)
        .modifier(CanvasDockGlass(shape: shape, dark: scheme == .dark))
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.6), .white.opacity(scheme == .dark ? 0.06 : 0.2), .white.opacity(0.3)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
            .allowsHitTesting(false))
        .padding(CanvasDockView.shadowRoom)
    }
}

/// The shelf: Liquid Glass on macOS 26; before that, the thinnest material
/// with a shadow.
private struct CanvasDockGlass<S: Shape>: ViewModifier {
    let shape: S
    let dark: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(dark ? .black.opacity(0.2) : .white.opacity(0.2)), in: shape)
        } else {
            content.background(
                shape.fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: 12, y: 4))
        }
    }
}

/// An app's icon, as iOS 26 draws one: a squircle of color with light
/// across its top and a bright edge, the symbol on it. It grows a little
/// under the pointer, and names itself in a tooltip.
struct CanvasDockIcon: View {
    static let size: CGFloat = 50

    let name: String
    let symbol: String
    /// The color at its top, then at its bottom.
    let colors: [Color]
    let glyph: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.size * 0.225, style: .continuous)
        Button(action: action) {
            ZStack {
                shape.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                shape.fill(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0)], startPoint: .top, endPoint: .center))
                Image(systemName: symbol)
                    .font(.system(size: Self.size * 0.5, weight: .medium))
                    .foregroundStyle(glyph)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.75), .white.opacity(0.08), .white.opacity(0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            }
            .frame(width: Self.size, height: Self.size)
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            .scaleEffect(hovered && !reduceMotion ? 1.08 : 1)
            .animation(.spring(duration: 0.25), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(name)
        .accessibilityLabel(name)
    }
}
#endif
