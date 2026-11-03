#if os(macOS)
import SwiftUI

/// A dictation about to send itself (VoiceAutoSend), drawn into Claude's
/// own frame: the line under its input box drains away, and its footer's
/// "REC · tap to send" becomes the seconds left and the key that keeps
/// you talking. Clicking the footer keeps you talking too.
struct VoiceAutoSendBadge: View {
    let surfaceID: UUID
    let cellSize: CGSize
    @ObservedObject private var voice = VoiceAutoSend.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager
    @EnvironmentObject private var ghostty: Ghostty.App

    var body: some View {
        if let countdown = voice.countdowns[surfaceID] {
            let skin = skins.effectiveSkin(surfaceID)
            GeometryReader { geometry in
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    ZStack(alignment: .topLeading) {
                        if let y = countdown.ruleY {
                            drain(countdown, skin: skin, width: geometry.size.width - 2 * countdown.left, now: timeline.date)
                                .offset(x: countdown.left, y: y - 1)
                        }
                        if let y = countdown.footerY {
                            footer(countdown, skin: skin, now: timeline.date)
                                .frame(width: geometry.size.width - countdown.left - cellSize.width, alignment: .trailing)
                                .offset(x: 0, y: y - cellSize.height / 2)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .transition(.opacity)
        }
    }

    private func drain(_ countdown: VoiceCountdown, skin: Skin?, width: CGFloat, now: Date) -> some View {
        let accent = TraceColors.color(skin?.accent ?? ResolvedTrace.unskinnedColor)
        let accent2 = TraceColors.color(skin?.accent2 ?? ResolvedTrace.unskinnedColor2)
        return Capsule()
            .fill(LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing))
            .frame(width: max(0, width) * countdown.remaining(at: now), height: 2)
            .shadow(color: accent.opacity(0.6), radius: 4)
            .allowsHitTesting(false)
    }

    private func footer(_ countdown: VoiceCountdown, skin: Skin?, now: Date) -> some View {
        let accent = TraceColors.color(skin?.accent ?? ResolvedTrace.unskinnedColor)
        let text = skin?.foreground.map { Color(rgb: $0) } ?? Color(nsColor: .labelColor)
        let background = skin.map { Color(rgb: $0.background) } ?? ghostty.config.backgroundColor
        return HStack(spacing: 0) {
            Text("sends in ").foregroundStyle(text.opacity(0.7))
            Text("\(countdown.secondsLeft(at: now))s").foregroundStyle(accent)
            Text(" · \(countdown.key) keep talking").foregroundStyle(text.opacity(0.7))
        }
        .font(.system(size: ClaudeReadyOverlay.fontSize(cellHeight: cellSize.height), design: .monospaced))
        .lineLimit(1)
        .padding(.leading, cellSize.width * 2)
        .frame(height: cellSize.height)
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture { voice.hold(surfaceID) }
        .help("Keep talking: the message waits until you say more")
    }
}
#endif
