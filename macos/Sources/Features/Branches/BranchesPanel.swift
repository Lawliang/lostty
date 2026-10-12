#if os(macOS)
import SwiftUI

/// The Branches app, inside the widened sidebar.
struct BranchesPanel: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BranchesHeader(title: "Branches", subtitle: nil, busy: false, onClose: onClose)
            Divider().overlay(LosttyTheme.hairline)
            Spacer(minLength: 0)
        }
        .modifier(PanelEscape(onClose: onClose))
    }
}

/// "‹ Apps" on the left, the repo on the right.
struct BranchesHeader: View {
    let title: String
    let subtitle: String?
    let busy: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Apps").font(.system(size: 12))
                }
                .foregroundStyle(LosttyTheme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to apps")
            Spacer(minLength: 8)
            if busy { ProgressView().controlSize(.small) }
            VStack(alignment: .trailing, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LosttyTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(LosttyTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Esc closes the panel, but only once the panel has focus (a click inside
/// it): Esc typed in the terminal stays with the terminal.
struct PanelEscape: ViewModifier {
    let onClose: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .focusable()
            .focused($focused)
            .onTapGesture { focused = true }
            .onExitCommand(perform: onClose)
    }
}
#endif
