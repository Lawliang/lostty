#if os(macOS)
import SwiftUI

/// A pane's countdown to its clear (ContextHandoffCoordinator.countdowns).
struct ContextHandoffCountdown: Equatable {
    var start: Date
    var seconds: TimeInterval
    /// What the agent was on, from its handoff's "Where we are".
    var summary: String

    /// 1 at the start, 0 when the window clears.
    func remaining(at date: Date) -> Double {
        guard seconds > 0 else { return 0 }
        return min(1, max(0, 1 - date.timeIntervalSince(start) / seconds))
    }

    /// Whole seconds left, rounded up: "Starting in 5s" first, never 0s.
    func secondsLeft(at date: Date) -> Int {
        max(1, Int((seconds - date.timeIntervalSince(start)).rounded(.up)))
    }
}

/// Over a pane about to hand off: a card in the pane's skin saying a fresh
/// conversation starts from the handoff, a bar emptying over the
/// countdown, and Skip. Left alone, the window clears when the bar runs
/// out; Skip (or typing in the pane) keeps this conversation, and the agent
/// hands off again at its next clean break.
struct ContextHandoffCountdownCard: View {
    let surfaceID: UUID
    @ObservedObject private var coordinator = ContextHandoffCoordinator.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        if let countdown = coordinator.countdowns[surfaceID] {
            let colors = ContextHandoffCardColors(skin: skins.effectiveSkin(surfaceID))
            ZStack {
                Color.black.opacity(0.35).allowsHitTesting(false)
                // 30 a second is smooth for a bar emptying over seconds.
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    card(countdown, colors: colors, now: timeline.date)
                }
            }
            .transition(.opacity)
        }
    }

    private func card(_ countdown: ContextHandoffCountdown, colors: ContextHandoffCardColors, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("❯ ").foregroundStyle(colors.accent)
                Text("Handing off to a fresh conversation").foregroundStyle(colors.text)
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            if !countdown.summary.isEmpty {
                Text(countdown.summary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(colors.text.opacity(0.7))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors.text.opacity(0.15))
                    Capsule().fill(colors.accent)
                        .frame(width: geometry.size.width * countdown.remaining(at: now))
                }
            }
            .frame(height: 4)
            HStack {
                Text("Starting in \(countdown.secondsLeft(at: now))s")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(colors.text.opacity(0.6))
                Spacer()
                Button("Skip") { coordinator.skip(surfaceID) }
                    .buttonStyle(ContextHandoffSkipStyle(colors: colors))
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.background))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(colors.accent.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
    }
}

/// The pane's skin as the card wears it; an unskinned pane gets the
/// window's colors and the trace's own accent.
struct ContextHandoffCardColors {
    var background: Color
    var text: Color
    var accent: Color

    init(skin: Skin?) {
        background = skin.map { Color(rgb: $0.background) } ?? Color(nsColor: .windowBackgroundColor)
        text = skin?.foreground.map { Color(rgb: $0) } ?? Color(nsColor: .labelColor)
        accent = TraceColors.color(skin?.accent ?? ResolvedTrace.unskinnedColor)
    }
}

private struct ContextHandoffSkipStyle: ButtonStyle {
    let colors: ContextHandoffCardColors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(colors.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Capsule().fill(colors.accent.opacity(configuration.isPressed ? 0.3 : 0.15)))
            .overlay(Capsule().strokeBorder(colors.accent.opacity(0.6), lineWidth: 1))
    }
}
#endif
