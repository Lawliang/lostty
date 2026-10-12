import SwiftUI

/// Lostty's buttons: primary (magenta), secondary (card), quiet (text),
/// quiet danger (red text).
struct LosttyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, quietDanger }

    var kind: Kind
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        LosttyButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }
}

private struct LosttyButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: LosttyButtonStyle.Kind
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var quiet: Bool { kind == .quiet || kind == .quietDanger }

    var body: some View {
        configuration.label
            .font(kind == .primary ? LosttyFont.button : LosttyFont.bodyEmphasis)
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, quiet ? 6 : 12)
            .padding(.horizontal, quiet ? 4 : 18)
            .background {
                switch kind {
                case .primary:
                    RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous)
                        .fill(LosttyTheme.accent.opacity(configuration.isPressed ? 0.8 : 1))
                case .secondary:
                    RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous)
                        .fill(configuration.isPressed ? LosttyTheme.surfaceRaised : LosttyTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: LosttyTheme.radius, style: .continuous)
                            .strokeBorder(LosttyTheme.hairline, lineWidth: 1))
                case .quiet, .quietDanger:
                    Color.clear
                }
            }
            .opacity(isEnabled ? (quiet && configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Rectangle())
            .animation(LosttyTheme.motion, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: LosttyTheme.textPrimary
        case .quiet: LosttyTheme.textSecondary
        case .quietDanger: LosttyTheme.danger
        }
    }
}

extension ButtonStyle where Self == LosttyButtonStyle {
    static func lostty(_ kind: LosttyButtonStyle.Kind, fullWidth: Bool = false) -> LosttyButtonStyle {
        LosttyButtonStyle(kind: kind, fullWidth: fullWidth)
    }
}
