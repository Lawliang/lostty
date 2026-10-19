#if os(macOS)
import SwiftUI

/// A card zoomed far out: a tile in its pane's skin colors with the
/// project, the agent state and what Claude is doing ("Editing
/// Foo.swift"). Clicking it zooms to the card.
struct CardTile: View {
    @ObservedObject var card: CardController
    /// The canvas's zoom: the tile is laid out at screen size and scaled
    /// up, so its text reads the same however far out.
    let zoom: CGFloat
    let open: () -> Void
    @ObservedObject private var claude = ClaudeRuntime.shared
    @ObservedObject private var activity = PaneActivity.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width * zoom, height: geo.size.height * zoom, alignment: .topLeading)
                .scaleEffect(1 / zoom, anchor: .topLeading)
        }
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var panes: [UUID] { card.surfaceTree.map(\.id) }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProjectPill(model: card.header)
            if let status = CardStatus.of(
                panes: panes, awaiting: claude.awaiting, phases: claude.phases,
                known: activity.known, lastActivity: activity.lastActivity, now: Date()) {
                CardStatusLabel(status: status, size: 13)
            }
            if let action = panes.lazy.compactMap({ claude.actions[$0] }).first {
                Text(action)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    private var background: Color {
        guard let pane = card.focusedSurface?.id ?? panes.first, let skin = skins.effectiveSkin(pane) else {
            return Color(nsColor: .windowBackgroundColor)
        }
        return TraceColors.color(skin.background)
    }
}
#endif
