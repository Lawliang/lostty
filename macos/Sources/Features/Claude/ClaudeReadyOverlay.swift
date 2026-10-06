#if os(macOS)
import SwiftUI

/// "Ready for response": shown over a pane whose Claude finished (or asks
/// for permission) while you were elsewhere. The pane dims and blurs, and a
/// single terminal line floats in the middle at the terminal's own text
/// size: a prompt in the skin's accent, the words, and a blinking block
/// cursor. Clicks pass through, so clicking the pane focuses it, which
/// dismisses the overlay.
struct ClaudeReadyOverlay: View {
    let surfaceID: UUID
    /// The pane's cell size in points, to match the terminal's text size.
    let cellSize: CGSize
    @ObservedObject private var runtime = ClaudeRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        if runtime.awaiting.contains(surfaceID) {
            ReadyLine(
                fontSize: Self.fontSize(cellHeight: cellSize.height),
                accent: Self.accent(for: skins.effectiveSkin(surfaceID)))
                .allowsHitTesting(false)
        }
    }

    /// SF Mono's line is about 1.2em tall, so this matches one terminal row.
    static func fontSize(cellHeight: CGFloat) -> CGFloat {
        cellHeight > 0 ? cellHeight / 1.2 : 13
    }

    static func accent(for skin: Skin?) -> Color {
        TraceColors.color(skin?.accent ?? ResolvedTrace.unskinnedColor)
    }
}

private struct ReadyLine: View {
    let fontSize: CGFloat
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cursorOn = true

    var body: some View {
        ZStack {
            // Dimmed, softly blurred pane.
            Rectangle().fill(.ultraThinMaterial).opacity(0.6)
            Color.black.opacity(0.45)

            HStack(spacing: 0) {
                Text("❯ ").foregroundStyle(accent)
                Text("Ready for response ").foregroundStyle(Color.white.opacity(0.92))
                Text("█").foregroundStyle(Color.white.opacity(cursorOn ? 0.85 : 0))
            }
            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
        }
        .task {
            guard !reduceMotion else { return }
            // A terminal cursor's blink: on and off about every half second.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                cursorOn.toggle()
            }
        }
    }
}
#endif
