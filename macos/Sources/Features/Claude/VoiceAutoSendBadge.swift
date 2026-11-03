#if os(macOS)
import SwiftUI

/// At the foot of a pane whose dictation is about to send itself
/// (VoiceAutoSend): the seconds left, and Keep talking, which waits.
struct VoiceAutoSendBadge: View {
    let surfaceID: UUID
    @ObservedObject private var voice = VoiceAutoSend.shared
    @ObservedObject private var skins = SkinsRuntime.shared.manager

    var body: some View {
        if let sendsAt = voice.countdowns[surfaceID] {
            let colors = ContextHandoffCardColors(skin: skins.effectiveSkin(surfaceID))
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                badge(seconds: max(1, Int(sendsAt.timeIntervalSince(timeline.date).rounded(.up))), colors: colors)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 28)
            .transition(.opacity)
        }
    }

    private func badge(seconds: Int, colors: ContextHandoffCardColors) -> some View {
        HStack(spacing: 10) {
            Text("Sending in \(seconds)s")
                .foregroundStyle(colors.text)
            Button("Keep talking") { voice.hold(surfaceID) }
                .buttonStyle(.plain)
                .foregroundStyle(colors.accent)
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(colors.background))
        .overlay(Capsule().strokeBorder(colors.accent.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
        .help("Press the voice key again to keep talking")
    }
}
#endif
