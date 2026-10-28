#if os(macOS)
import Combine
import Foundation
import SwiftUI

/// A request's end in a pane, with what it cost.
struct GoldDrop: Identifiable, Equatable {
    /// Fresh each time, so two drops with the same count both play.
    let id = UUID()
    var pane: UUID
    var tokens: Int
}

/// App-wide: when a Claude request ends in a pane, weighs its tokens and
/// drops gold coins in that pane's corner (`GoldDropOverlay`).
@MainActor
final class GoldDropRuntime {
    static let shared = GoldDropRuntime()

    let drops = PassthroughSubject<GoldDrop, Never>()
    private let counter = RequestTokens()

    func requestEnded(pane: UUID, path: String, since: Date) {
        // Codex writes its tokens another way.
        guard let location = TranscriptLocation.allowed(path), location.agent == .claude else { return }
        Task {
            let tokens = await counter.total(location.url, since: since)
            if tokens > 0 { drops.send(GoldDrop(pane: pane, tokens: tokens)) }
        }
    }

    /// "222k": a request's tokens, short.
    static func label(_ tokens: Int) -> String {
        if tokens < 1_000 { return "\(tokens)" }
        func tenths(_ value: Int, _ unit: String) -> String {
            value % 10 == 0 ? "\(value / 10)\(unit)" : "\(value / 10).\(value % 10)\(unit)"
        }
        let hundreds = (tokens + 50) / 100
        if hundreds < 100 { return tenths(hundreds, "k") }
        let thousands = (tokens + 500) / 1_000
        if thousands < 1_000 { return "\(thousands)k" }
        return tenths((tokens + 50_000) / 100_000, "M")
    }
}

/// Gold coins dropping onto a little stack in a pane's bottom-right corner
/// as a Claude request ends there, with what it cost. Clicks pass through.
struct GoldDropOverlay: View {
    let surfaceID: UUID
    @State private var drop: GoldDrop?

    var body: some View {
        Color.clear
            .overlay(alignment: .bottomTrailing) {
                if let drop {
                    GoldDropView(label: GoldDropRuntime.label(drop.tokens))
                        .id(drop.id)
                        .padding(12)
                }
            }
            .allowsHitTesting(false)
            .onReceive(GoldDropRuntime.shared.drops) { drop in
                if drop.pane == surfaceID { self.drop = drop }
            }
            .task(id: drop?.id) {
                guard drop != nil else { return }
                try? await Task.sleep(for: .seconds(GoldDropAnimation.duration))
                if !Task.isCancelled { drop = nil }
            }
    }
}

/// The drop as a function of time since it began: coins fall in one after
/// another, spinning, bounce a little as they land on the stack, the count
/// fades in as the first one lands, and everything fades out at the end.
enum GoldDropAnimation {
    static let duration = 1.5
    static let coins = 6
    static let coinSize: CGFloat = 14
    /// How much higher each coin on the stack sits than the one under it.
    static let step: CGFloat = 3.5
    static let stagger = 0.07
    static let fall = 0.42
    static let height: CGFloat = 80
    static let bounce = 0.12
    static let bounceHeight: CGFloat = 3
    static let spins = 2.0
    static let labelFade = 0.2
    static let fadeOut = 0.3

    struct Coin: Equatable {
        /// How far above its place on the stack, in points.
        var lift: CGFloat
        /// Horizontal scale, for the spin: 1 is face on.
        var spin: CGFloat
        var opacity: Double
    }

    struct Frame: Equatable {
        var coins: [Coin]
        var label: Double
        /// Over everything, for the fade out.
        var opacity: Double
    }

    static func frame(at t: Double, reduceMotion: Bool) -> Frame {
        func ramp(_ x: Double) -> Double { min(1, max(0, x)) }
        let fadeOut = ramp((duration - t) / Self.fadeOut)
        guard !reduceMotion else {
            let shown = min(ramp(t / labelFade), fadeOut)
            return Frame(coins: Array(repeating: Coin(lift: 0, spin: 1, opacity: 1), count: coins), label: 1, opacity: shown)
        }
        let stack = (0..<coins).map { index -> Coin in
            let falling = t - Double(index) * stagger
            guard falling >= 0 else { return Coin(lift: height, spin: 1, opacity: 0) }
            let progress = ramp(falling / fall)
            if progress < 1 {
                // Gravity: the distance fallen grows with the square of time.
                let lift = height * CGFloat(1 - progress * progress)
                let spin = CGFloat(max(0.15, abs(cos(spins * 2 * .pi * (1 - progress)))))
                return Coin(lift: lift, spin: spin, opacity: ramp(progress / 0.15))
            }
            let landed = (falling - fall) / bounce
            let lift = landed < 1 ? bounceHeight * CGFloat(sin(.pi * landed)) : 0
            return Coin(lift: lift, spin: 1, opacity: 1)
        }
        return Frame(coins: stack, label: ramp((t - fall) / labelFade), opacity: fadeOut)
    }
}

private struct GoldDropView: View {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let frame = GoldDropAnimation.frame(at: timeline.date.timeIntervalSince(start), reduceMotion: reduceMotion)
            HStack(alignment: .bottom, spacing: 6) {
                Text(label)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(
                        colors: [GoldCoin.light, GoldCoin.gold], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.75), radius: 1.5, y: 1)
                    .opacity(frame.label)
                ZStack(alignment: .bottom) {
                    ForEach(Array(frame.coins.enumerated()), id: \.offset) { index, coin in
                        GoldCoin()
                            .scaleEffect(x: coin.spin, y: 1)
                            // Every other coin sits a little off, like a real pile.
                            .offset(x: index.isMultiple(of: 2) ? 0 : 1.5,
                                    y: -(CGFloat(index) * GoldDropAnimation.step + coin.lift))
                            .opacity(coin.opacity)
                    }
                }
                .frame(
                    width: GoldDropAnimation.coinSize + 1.5,
                    height: GoldDropAnimation.coinSize + CGFloat(GoldDropAnimation.coins - 1) * GoldDropAnimation.step,
                    alignment: .bottomLeading)
            }
            .opacity(frame.opacity)
        }
    }
}

private struct GoldCoin: View {
    static let light = Color(red: 1, green: 0.95, blue: 0.66)
    static let gold = Color(red: 1, green: 0.78, blue: 0.2)
    static let dark = Color(red: 0.78, green: 0.53, blue: 0.08)
    static let rim = Color(red: 0.5, green: 0.32, blue: 0)

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [Self.light, Self.gold, Self.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Self.rim, lineWidth: 1.2)
            Circle().strokeBorder(Self.light.opacity(0.8), lineWidth: 0.8).padding(3)
        }
        .frame(width: GoldDropAnimation.coinSize, height: GoldDropAnimation.coinSize)
        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
    }
}
#endif
