#if os(macOS)
import AppKit
import SwiftUI

/// A dictation about to send itself (VoiceAutoSend), drawn into Claude's
/// own frame: its footer's "REC · tap to send" becomes the seconds left
/// and the key that keeps you talking. Clicking the footer keeps you
/// talking too. The seconds change once a second.
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
                ZStack(alignment: .topLeading) {
                    if let y = countdown.footerY {
                        // Once a second, on the countdown's own seconds.
                        let start = countdown.sendsAt.addingTimeInterval(-VoiceWatch.countdown)
                        TimelineView(.periodic(from: start, by: 1)) { timeline in
                            footer(countdown, skin: skin, now: timeline.date)
                        }
                        .frame(width: max(0, geometry.size.width - countdown.left - cellSize.width), alignment: .trailing)
                        .offset(x: 0, y: y - cellSize.height / 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .transition(.opacity)
        }
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
