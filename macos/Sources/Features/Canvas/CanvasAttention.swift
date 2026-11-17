#if os(macOS)
import AppKit
import SwiftUI

/// Arrows at the canvas's edges, as in a top-down game: each card off
/// screen whose terminal finished and waits on you shows an avatar on the
/// edge nearest it, with an arrow pointing its way. Markers that would
/// overlap become one, with a count. Notifications → Arrows in Lostty Settings.
enum CanvasAttention {
    /// A waiting pane and its card's frame, in canvas points.
    struct Target: Equatable {
        let pane: UUID
        var frame: CGRect
        var name: String?
    }

    /// Where a marker sits in the canvas view (points, y down), and the way
    /// its arrow points (radians, 0 is right, y down). Its first pane is
    /// the oldest waiting.
    struct Marker: Equatable, Identifiable {
        var panes: [UUID]
        var center: CGPoint
        var angle: CGFloat
        var name: String?

        var id: UUID { panes[0] }
    }

    /// From the window's edge to a marker's center.
    static let inset: CGFloat = 40
    /// Markers closer than this merge.
    static let spacing: CGFloat = 56

    /// The markers for `targets`, oldest first, on a view of `size` showing
    /// `shown` (canvas points) at `zoom`. A card any part of which shows
    /// gets none.
    static func markers(_ targets: [Target], shown: CGRect, zoom: CGFloat, size: CGSize) -> [Marker] {
        guard size.width > 2 * inset, size.height > 2 * inset, zoom > 0 else { return [] }
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        let reach = CGSize(width: middle.x - inset, height: middle.y - inset)
        var markers: [Marker] = []
        for target in targets where !target.frame.intersects(shown) {
            let card = CGPoint(x: (target.frame.midX - shown.minX) * zoom, y: (target.frame.midY - shown.minY) * zoom)
            let way = CGVector(dx: card.x - middle.x, dy: card.y - middle.y)
            let scale = min(way.dx == 0 ? .infinity : reach.width / abs(way.dx),
                            way.dy == 0 ? .infinity : reach.height / abs(way.dy))
            guard scale.isFinite else { continue }
            let center = CGPoint(x: middle.x + way.dx * scale, y: middle.y + way.dy * scale)
            if let near = markers.firstIndex(where: { hypot($0.center.x - center.x, $0.center.y - center.y) < spacing }) {
                markers[near].panes.append(target.pane)
            } else {
                markers.append(Marker(panes: [target.pane], center: center, angle: atan2(way.dy, way.dx), name: target.name))
            }
        }
        return markers
    }
}

@MainActor
final class CanvasAttentionState: ObservableObject {
    @Published var markers: [CanvasAttention.Marker] = []
    var open: (UUID) -> Void = { _ in }
}

/// Over the cards, under the notification stack. Clicks pass through but
/// on a marker.
final class CanvasAttentionView: NSHostingView<CanvasAttentionMarkers> {
    let state: CanvasAttentionState

    init() {
        let state = CanvasAttentionState()
        self.state = state
        super.init(rootView: CanvasAttentionMarkers(state: state))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @available(*, unavailable)
    required init(rootView: CanvasAttentionMarkers) { fatalError("init(rootView:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let flipped = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        let radius = CanvasAttentionMarker.size / 2 + 4
        guard state.markers.contains(where: { hypot($0.center.x - flipped.x, $0.center.y - flipped.y) <= radius }) else {
            return nil
        }
        return super.hitTest(point)
    }
}

struct CanvasAttentionMarkers: View {
    @ObservedObject var state: CanvasAttentionState

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(state.markers) { marker in
                CanvasAttentionMarker(marker: marker)
                    .position(marker.center)
                    .onTapGesture { state.open(marker.id) }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.markers.map(\.id))
    }
}

/// An avatar in a ring, the arrow outside it pointing at the card, and a
/// count when it stands for more than one.
struct CanvasAttentionMarker: View {
    static let size: CGFloat = 44
    let marker: CanvasAttention.Marker

    var body: some View {
        ZStack {
            CanvasAttentionArrow()
                .fill(LosttyTheme.accent)
                .frame(width: 12, height: 14)
                .offset(x: Self.size / 2 + 8)
                .rotationEffect(.radians(marker.angle))
            Circle()
                .fill(LosttyTheme.surfaceRaised)
                .overlay(Axolotl(pose: .waving, moves: false).padding(5))
                .overlay(Circle().strokeBorder(LosttyTheme.accent, lineWidth: 2))
                .frame(width: Self.size, height: Self.size)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
            if marker.panes.count > 1 {
                Text("\(marker.panes.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(LosttyTheme.accent))
                    .offset(x: Self.size / 2 - 4, y: -Self.size / 2 + 4)
            }
        }
        .frame(width: Self.size + 40, height: Self.size + 40)
        .contentShape(Circle().size(width: Self.size, height: Self.size).offset(x: 20, y: 20))
        .help(marker.name.map { "\($0) needs you" } ?? "A terminal needs you")
        .accessibilityElement()
        .accessibilityLabel(marker.name.map { "\($0) needs you" } ?? "A terminal needs you")
        .accessibilityAddTraits(.isButton)
    }
}

/// A triangle pointing right.
struct CanvasAttentionArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
#endif
