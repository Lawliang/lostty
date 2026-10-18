#if os(macOS)
import AppKit
import SwiftUI

/// The floating pill on the right edge of a window whose sidebar hides:
/// click it to show the sidebar, or drag it left and the sidebar follows.
/// While the sidebar shows, it rides on its left edge to close it again.
struct SidebarHandle: View {
    /// Wide enough to grab; the pill sits in the middle.
    static let hitWidth: CGFloat = 16

    let open: Bool
    let onTap: () -> Void
    let onDrag: (CGFloat) -> Void
    let onDragEnd: (_ predicted: CGFloat) -> Void
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        let lit = hovering || dragging
        Capsule()
            .fill(Color.white.opacity(lit ? 0.75 : 0.4))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
            .frame(width: lit ? 6 : 4, height: lit ? 52 : 44)
            .shadow(color: .black.opacity(0.45), radius: 3)
            .frame(width: Self.hitWidth, height: 76)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: lit)
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if hovering { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        guard dragging || abs(value.translation.width) > 3 else { return }
                        dragging = true
                        onDrag(value.translation.width)
                    }
                    .onEnded { value in
                        if dragging {
                            onDragEnd(value.predictedEndTranslation.width)
                        } else {
                            onTap()
                        }
                        dragging = false
                    })
            .help(open ? "Click or drag right to hide the sidebar" : "Click or drag left to show the sidebar")
            .accessibilityElement()
            .accessibilityLabel(open ? "Hide sidebar" : "Show sidebar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
    }
}
#endif
