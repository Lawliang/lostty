#if os(macOS)
import SwiftUI

/// "Ready for response": shown over a pane whose Claude finished (or asks
/// for permission) while you were elsewhere. The pane dims and blurs like
/// the backdrop of an iOS alert, with plain white monospaced text on it.
/// Clicks pass through, so clicking the pane focuses it, which dismisses
/// the overlay.
struct ClaudeReadyOverlay: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared

    var body: some View {
        if runtime.awaiting.contains(surfaceID) {
            ReadyScreen()
                .allowsHitTesting(false)
        }
    }
}

private struct ReadyScreen: View {
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
                .font(.system(size: size, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .fixedSize()
            }
        }
    }

    /// As big as fits: "response" (8 monospaced cells, ~0.6em each) spans
    /// at most ~60% of the pane's width, and the text block at most ~60% of
    /// its height.
    static func fontSize(for size: CGSize) -> CGFloat {
        let byWidth = size.width * 0.6 / (8 * 0.6)
        let byHeight = size.height * 0.6 / 4.3
        return max(13, min(72, byWidth, byHeight))
    }
}
#endif
