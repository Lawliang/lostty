#if os(macOS)
import SwiftUI

/// The top-right stack of notification bubbles over the terminal area.
struct NotificationStackView: View {
    @ObservedObject var center: LosttyNotifications = .shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.items) { item in
                NotificationBubble(item: item, center: center)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.items.map(\.id))
    }
}

/// An iOS-style banner: frosted rounded card, icon, title, one line of
/// detail, an optional action and a close button.
private struct NotificationBubble: View {
    let item: LosttyNotification
    let center: LosttyNotifications

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle = item.actionTitle, let action = item.action {
                    Button(actionTitle) { action() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor))
                        .padding(.top, 6)
                }
            }

            Spacer(minLength: 0)

            Button { center.dismiss(item.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .environment(\.colorScheme, .dark)
        .onAppear { center.markShown(item.id) }
        .onHover { center.setHovering(item.id, $0) }
    }

    private var icon: String {
        switch item.style {
        case .attention: "link"
        case .success: "checkmark"
        case .failure: "exclamationmark"
        }
    }

    private var tint: Color {
        switch item.style {
        case .attention: Color(red: 0.36, green: 0.36, blue: 0.95)
        case .success: Color(red: 0.2, green: 0.7, blue: 0.4)
        case .failure: Color(red: 0.9, green: 0.36, blue: 0.3)
        }
    }
}
#endif
