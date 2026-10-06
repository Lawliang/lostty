#if os(macOS)
import SwiftUI

/// "Ready for response": shown over a pane whose Claude finished (or asks
/// for permission) while you were elsewhere. The racing trace comes to rest
/// as a breathing rim of light in the skin's colors, over a frosted,
/// vignetted pane. Clicks pass through, so clicking the pane focuses it,
/// which dismisses the overlay.
struct ClaudeReadyOverlay: View {
    let surfaceID: UUID
    @ObservedObject private var runtime = ClaudeRuntime.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        if runtime.awaiting.contains(surfaceID) {
            ReadyCard(colors: Self.colors(for: skins.effectiveSkin(surfaceID)))
                .allowsHitTesting(false)
        }
    }

    /// The pane's trace colors, even when traces are turned off.
    static func colors(for skin: Skin?) -> TraceColors {
        if let trace = ResolvedTrace.resolve(skin: skin, enabled: true) { return TraceColors(trace) }
        let accent = skin?.accent ?? ResolvedTrace.unskinnedColor
        return TraceColors(primary: accent, secondary: skin?.accent2 ?? accent.mixed(with: .white, amount: 0.4))
    }
}

private struct ReadyCard: View {
    let colors: TraceColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private static let words = ["Ready", "for", "response"]

    var body: some View {
        GeometryReader { geo in
            let size = Self.fontSize(for: geo.size)
            ZStack {
                // Frosted pane (the terminal still shows faintly), darker
                // toward the edges.
                Rectangle().fill(.ultraThinMaterial).opacity(0.7)
                RadialGradient(
                    colors: [Color.black.opacity(0.58), Color.black.opacity(0.88)],
                    center: .center, startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.7)

                // The trace at rest: a rim of light that slowly breathes.
                rim
                    .opacity(reduceMotion ? 0.9 : (breathe ? 1 : 0.55))

                VStack(spacing: -size * 0.16) {
                    ForEach(Self.words, id: \.self) { word in
                        Text(word).lineLimit(1)
                    }
                }
                .font(.system(size: size, weight: .black, design: .rounded))
                .tracking(-size * 0.025)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: colors.head.opacity(0.9), radius: size * 0.12)
                .shadow(color: colors.tail.opacity(0.5), radius: size * 0.45)
                .fixedSize()
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    private var rim: some View {
        let gradient = AngularGradient(
            colors: [colors.head, colors.tail, colors.head, colors.tail, colors.head], center: .center)
        return ZStack {
            Rectangle().inset(by: TraceOverlay.inset).stroke(gradient, lineWidth: 16).blur(radius: 18)
            Rectangle().inset(by: TraceOverlay.inset).stroke(gradient, lineWidth: 4).blur(radius: 2)
            Rectangle().inset(by: TraceOverlay.inset).stroke(Color.white.opacity(0.85), lineWidth: 1.2)
        }
        .blendMode(.plusLighter)
    }

    /// As big as fits: "response" (the widest word) spans at most ~78% of
    /// the width, and the three lines at most ~70% of the height.
    static func fontSize(for size: CGSize) -> CGFloat {
        let byWidth = size.width * 0.78 / (8 * 0.6)
        let byHeight = size.height * 0.7 / 3
        return max(14, min(120, byWidth, byHeight))
    }
}
#endif
