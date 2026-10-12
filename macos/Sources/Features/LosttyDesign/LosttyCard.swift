import SwiftUI

/// A rounded surface with a hairline border.
struct LosttyCard<Content: View>: View {
    var padding: CGFloat
    let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LosttyTheme.surface,
                        in: RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous)
                .strokeBorder(LosttyTheme.hairline, lineWidth: 1))
    }
}

enum StatusRowStatus { case ok, warning, missing }

/// A checklist row: status dot, title, wrapping detail, and fix buttons under it.
struct StatusRow<Trailing: View>: View {
    var status: StatusRowStatus
    var title: String
    var detail: String
    let trailing: Trailing

    init(status: StatusRowStatus, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) {
        self.status = status
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(color)
                Image(systemName: glyph)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LosttyTheme.background)
            }
            .frame(width: 18, height: 18)
            .padding(.top, 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status == .ok ? "Ready" : status == .warning ? "Needs attention" : "Not ready")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LosttyFont.bodyEmphasis).foregroundStyle(LosttyTheme.textPrimary)
                Text(detail).font(LosttyFont.detail).foregroundStyle(LosttyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                // Fix buttons sit under the text so the text keeps the full width.
                FlowLayout(spacing: 8, topPadding: 8) { trailing }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }

    private var glyph: String {
        switch status {
        case .ok: "checkmark"
        case .warning: "exclamationmark"
        case .missing: "xmark"
        }
    }

    private var color: Color {
        switch status {
        case .ok: LosttyTheme.success
        case .warning: LosttyTheme.warning
        case .missing: LosttyTheme.danger
        }
    }
}
