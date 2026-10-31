#if os(macOS)
import LosttyRemote
import SwiftUI

/// The temporary notifications, under the regular ones: fresh ones in
/// full, then the collapsed ones as a dimmed deck that fans out on hover.
struct TerminalNoticeStack: View {
    @ObservedObject var center: TerminalNotices = .shared
    @State private var fanned = false

    private var fresh: [TerminalNotice] { center.items.filter { !center.collapsed.contains($0.id) } }
    private var deck: [TerminalNotice] { center.items.filter { center.collapsed.contains($0.id) } }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(fresh) { item in
                TerminalNoticeCard(item: item, compact: false)
                    .onTapGesture { center.open(item) }
                    .onHover { center.setHovering(item.id, $0) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if !deck.isEmpty { deckView }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.items.map(\.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.collapsed)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: fanned)
    }

    @ViewBuilder private var deckView: some View {
        Group {
            if fanned {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(deck) { item in
                        TerminalNoticeCard(item: item, compact: true)
                            .onTapGesture { center.open(item) }
                    }
                }
            } else {
                ZStack(alignment: .top) {
                    ForEach(Array(deck.prefix(3).enumerated()), id: \.element.id) { index, item in
                        TerminalNoticeCard(item: item, compact: true)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.black.opacity(index == 0 ? 0.45 : 0.85)))
                            .scaleEffect(1 - CGFloat(index) * 0.05, anchor: .top)
                            .offset(y: CGFloat(index) * 7)
                            .zIndex(Double(-index))
                    }
                }
                .padding(.bottom, CGFloat(min(deck.count, 3) - 1) * 7)
                .overlay(alignment: .topLeading) {
                    if deck.count > 1 {
                        Text("\(deck.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .offset(x: -6, y: -6)
                    }
                }
                .opacity(0.85)
            }
        }
        .onHover { fanned = $0 }
    }
}

/// One temporary notification, in its pane's skin: the project pill, the
/// pane's title, and, in full, the request and the agent's last reply.
private struct TerminalNoticeCard: View {
    let item: TerminalNotice
    let compact: Bool
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        let skin = skins.effectiveSkin(item.pane)
        let colors = NoticeColors(skin: skin)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.onAccent)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(colors.accent))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let project = item.project {
                        ProjectPillCapsule(label: project, skin: skin, chrome: nil, maxWidth: compact ? 170 : 210)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                    Text("Ready")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(colors.secondary)
                        .fixedSize()
                }
                Text(item.title.isEmpty ? "Terminal" : item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.primary)
                    .lineLimit(1)
                if !compact {
                    if let request = item.recap.request { line("You", request, colors) }
                    if let reply = item.recap.reply { line("Claude", reply, colors) }
                }
            }
        }
        .padding(compact ? 9 : 12)
        .frame(width: compact ? 280 : 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.background))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(colors.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
        .help("Show this terminal")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func line(_ who: String, _ text: String, _ colors: NoticeColors) -> some View {
        (Text("\(who): ").fontWeight(.semibold) + Text(text))
            .font(.system(size: 12))
            .foregroundStyle(colors.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// A notice's colors: its pane's skin's, else the regular notifications'
/// dark frosted look.
private struct NoticeColors {
    var background: AnyShapeStyle
    var primary: Color
    var secondary: Color
    var accent: Color
    var onAccent: Color
    var border: Color

    init(skin: Skin?) {
        guard let skin = skin?.sessionSkin() else {
            background = AnyShapeStyle(.regularMaterial)
            primary = .primary
            secondary = .secondary
            accent = Color(red: 0.36, green: 0.36, blue: 0.95)
            onAccent = .white
            border = .white.opacity(0.12)
            return
        }
        let text = skin.foreground.map(Self.color) ?? (skin.isLight ? Color(white: 0.11) : Color(white: 0.95))
        background = AnyShapeStyle(Self.color(skin.background))
        primary = text
        secondary = text.opacity(0.7)
        accent = Self.color(skin.accent)
        onAccent = skin.accent.luminance > 0.5 ? .black : .white
        border = Self.color(skin.accent).opacity(0.45)
    }

    private static func color(_ rgb: SessionSkin.RGB) -> Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}
#endif
