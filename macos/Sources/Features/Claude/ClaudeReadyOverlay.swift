#if os(macOS)
import SwiftUI

/// "Ready for response": shown over a pane whose Claude finished (or asks
/// for permission) while you were elsewhere. The pane dims and blurs, and a
/// single terminal line floats in the middle at the terminal's own text
/// size: a prompt in the skin's accent, the words typed out, and a
/// blinking block cursor (see `ReadyAnimation`). Clicks pass through, so clicking the pane focuses it, which
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

/// The "Ready for response" entrance, as a function of time since the
/// overlay appeared: the dark overlay fades in, then the prompt fades in with
/// a blinking cursor beside it, then the words type out quickly and the
/// cursor keeps blinking at the end.
enum ReadyAnimation {
    static let text = "Ready for response"
    static let overlayFade: Double = 0.35
    static let promptFade: Double = 0.2
    /// The cursor blinks beside the prompt for a beat before typing starts.
    static let promptHold: Double = 0.45
    static let perCharacter: Double = 0.032
    /// A terminal cursor's blink: on and off about every half second.
    static let blinkHalfPeriod: Double = 0.53

    static var typingStart: Double { overlayFade + promptFade + promptHold }
    static var typingEnd: Double { typingStart + perCharacter * Double(text.count) }

    /// The finished line, shown once the entrance is over.
    static var settledFrame: Frame { frame(at: typingEnd + 1, reduceMotion: false) }

    struct Frame: Equatable {
        /// Opacity of the dark overlay, 0...1.
        var overlay: Double
        /// Opacity of the prompt and cursor, 0...1.
        var prompt: Double
        /// Characters of `text` typed so far.
        var typed: Int
        /// True while characters are still appearing (the cursor stays solid).
        var typing: Bool
    }

    static func frame(at t: Double, reduceMotion: Bool) -> Frame {
        guard !reduceMotion else { return Frame(overlay: 1, prompt: 1, typed: text.count, typing: false) }
        func ramp(_ x: Double) -> Double { min(1, max(0, x)) }
        let overlay = ramp(t / overlayFade)
        let prompt = ramp((t - overlayFade) / promptFade)
        let typed = t < typingStart ? 0 : min(text.count, Int(((t - typingStart) / perCharacter).rounded(.down)) + 1)
        return Frame(overlay: overlay, prompt: prompt, typed: typed, typing: typed > 0 && typed < text.count)
    }

    static func cursorOn(at t: Double, reduceMotion: Bool) -> Bool {
        if reduceMotion || frame(at: t, reduceMotion: false).typing { return true }
        return Int((t / blinkHalfPeriod).rounded(.down)) % 2 == 0
    }
}

private struct ReadyLine: View {
    let fontSize: CGFloat
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    /// After the entrance only the cursor blinks, so the per-frame timeline
    /// stops and a slow toggle takes over.
    @State private var settled = false
    @State private var blinkOn = true

    var body: some View {
        TimelineView(.animation(paused: settled)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            let frame = settled ? ReadyAnimation.settledFrame : ReadyAnimation.frame(at: t, reduceMotion: reduceMotion)
            let cursor = settled ? (reduceMotion || blinkOn) : ReadyAnimation.cursorOn(at: t, reduceMotion: reduceMotion)
            ZStack {
                // Dimmed, softly blurred pane.
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).opacity(0.6)
                    Color.black.opacity(0.45)
                }
                .opacity(frame.overlay)

                // The finished line reserves its space, so typing never shifts it.
                ZStack(alignment: .leading) {
                    Text("❯ \(ReadyAnimation.text)█").opacity(0)
                    HStack(spacing: 0) {
                        Text("❯ ").foregroundStyle(accent)
                        Text(String(ReadyAnimation.text.prefix(frame.typed)))
                            .foregroundStyle(Color.white.opacity(0.92))
                        Text("█").foregroundStyle(Color.white.opacity(cursor ? 0.85 : 0))
                    }
                    .opacity(frame.prompt)
                }
                .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
            }
        }
        .task {
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(ReadyAnimation.typingEnd))
            }
            settled = true
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(ReadyAnimation.blinkHalfPeriod))
                blinkOn.toggle()
            }
        }
    }
}
#endif
