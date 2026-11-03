#if os(macOS)
import AppKit
import SwiftUI

/// A dictation about to send itself (VoiceAutoSend), drawn into Claude's
/// own frame: the line under its input box drains away, and its footer's
/// "REC · tap to send" becomes the seconds left and the key that keeps
/// you talking. Clicking the footer keeps you talking too. Core Animation
/// drains the line, so Lostty does nothing while it runs; the footer's
/// seconds change once a second.
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
                    if let y = countdown.ruleY {
                        VoiceDrainLine(
                            sendsAt: countdown.sendsAt,
                            start: LosttyWindowStyle.nsColor(skin?.accent ?? ResolvedTrace.unskinnedColor),
                            end: LosttyWindowStyle.nsColor(skin?.accent2 ?? ResolvedTrace.unskinnedColor2))
                            .frame(width: max(0, geometry.size.width - 2 * countdown.left), height: 1)
                            .offset(x: countdown.left, y: y - 0.5)
                    }
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

/// The draining line: one gradient layer whose width Core Animation
/// shrinks to nothing by `sendsAt`, at the display's own rate.
struct VoiceDrainLine: NSViewRepresentable {
    let sendsAt: Date
    let start: NSColor
    let end: NSColor

    func makeNSView(context: Context) -> VoiceDrainView { VoiceDrainView() }

    func updateNSView(_ view: VoiceDrainView, context: Context) {
        view.run(sendsAt: sendsAt, start: start, end: end)
    }
}

final class VoiceDrainView: NSView {
    private let bar = CAGradientLayer()
    private var running: Date?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bar.startPoint = CGPoint(x: 0, y: 0.5)
        bar.endPoint = CGPoint(x: 1, y: 0.5)
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.shadowOpacity = 0.5
        bar.shadowRadius = 2
        bar.shadowOffset = .zero
        layer?.addSublayer(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.bounds = bounds
        bar.position = CGPoint(x: 0, y: bounds.midY)
        bar.shadowPath = CGPath(rect: bounds, transform: nil)
        CATransaction.commit()
    }

    func run(sendsAt: Date, start: NSColor, end: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.colors = [start.cgColor, end.cgColor]
        bar.shadowColor = start.cgColor
        CATransaction.commit()
        guard running != sendsAt else { return }
        running = sendsAt
        let left = max(0, sendsAt.timeIntervalSinceNow)
        let drain = CABasicAnimation(keyPath: "transform.scale.x")
        drain.fromValue = min(1, left / VoiceWatch.countdown)
        drain.toValue = 0
        drain.duration = left
        bar.transform = CATransform3DMakeScale(0, 1, 1)
        bar.add(drain, forKey: "drain")
    }
}
#endif
