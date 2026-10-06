#if os(macOS)
import SwiftUI

/// "Ready for response": shown over a pane whose Claude finished (or asks
/// for permission) while you were elsewhere. iOS-style: the pane dims and
/// blurs like the backdrop of an alert, with a frosted card in the middle.
/// Clicks pass through, so clicking the pane focuses it, which dismisses
/// the overlay.
struct ClaudeReadyOverlay: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared

    var body: some View {
        if runtime.awaiting.contains(surfaceID) {
            ReadyCard()
                .allowsHitTesting(false)
        }
    }
}

private struct ReadyCard: View {
    private static let words = ["Ready", "for", "response"]

    var body: some View {
        GeometryReader { geo in
            let size = Self.fontSize(for: geo.size)
            ZStack {
                // Dimmed, softly blurred pane, like the backdrop behind an iOS alert.
                Rectangle().fill(.ultraThinMaterial).opacity(0.6)
                Color.black.opacity(0.4)

                VStack(spacing: size * 0.02) {
                    ForEach(Self.words, id: \.self) { word in
                        Text(word).lineLimit(1)
                    }
                }
                .font(.system(size: size, weight: .semibold))
                .tracking(-size * 0.01)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .fixedSize()
                .padding(.horizontal, size * 0.75)
                .padding(.vertical, size * 0.55)
                .background {
                    let card = RoundedRectangle(cornerRadius: size * 0.55, style: .continuous)
                    card.fill(.regularMaterial)
                        .overlay(card.fill(Color.black.opacity(0.25)))
                        .overlay(card.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.35), radius: size * 0.6, y: size * 0.2)
                }
                .environment(\.colorScheme, .dark)
            }
        }
    }

    /// As big as fits inside the card: "response" spans at most ~55% of the
    /// pane's width, and the card at most ~60% of its height.
    static func fontSize(for size: CGSize) -> CGFloat {
        let byWidth = size.width * 0.55 / 4.6
        let byHeight = size.height * 0.6 / 4.3
        return max(13, min(72, byWidth, byHeight))
    }
}
#endif
