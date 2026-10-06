#if os(macOS)
import Foundation

/// Trace animation timings (spec §4).
enum TraceTiming {
    static let fadeIn: TimeInterval = 0.2
    /// The tail stretches until it wraps the whole edge.
    static let closeLoop: TimeInterval = 0.4
    static let pulse: TimeInterval = 0.25
    static let finishFade: TimeInterval = 0.8
    static let exitFade: TimeInterval = 0.3
    static var finishTotal: TimeInterval { closeLoop + pulse + finishFade }
}

/// One pane's trace over time. `since` is when racing began; it survives a
/// finish cancelled by a new prompt, so the head never jumps.
enum TracePhase: Equatable {
    case off
    case racing(since: Date)
    case finishing(since: Date, at: Date)
    case fading(since: Date, at: Date)

    var isOff: Bool { self == .off }

    func applying(_ state: ClaudeState, now: Date) -> TracePhase {
        switch (state, self) {
        case (.busy, .off), (.busy, .fading):
            return .racing(since: now)
        case (.busy, .finishing(let since, _)):
            return .racing(since: since)
        case (.busy, .racing):
            return self
        case (.idle, .racing(let since)):
            return .finishing(since: since, at: now)
        case (.exit, .racing(let since)):
            return .fading(since: since, at: now)
        case (.idle, _), (.exit, _):
            return self
        }
    }

    /// Returns `.off` once a flash or fade has run its course.
    func settled(now: Date) -> TracePhase {
        switch self {
        case .finishing(_, let at) where now.timeIntervalSince(at) >= TraceTiming.finishTotal:
            return .off
        case .fading(_, let at) where now.timeIntervalSince(at) >= TraceTiming.exitFade:
            return .off
        default:
            return self
        }
    }
}

/// What to draw at one instant. Positions are fractions of the perimeter,
/// clockwise from the top-left corner.
struct TraceFrame: Equatable {
    /// Head position, 0..<1.
    var head: Double
    /// Tail length, 0...1.
    var length: Double
    /// Overall opacity, 0...1.
    var intensity: Double
    /// Whole-border finish flash, 0...1.
    var pulse: Double

    static func make(_ phase: TracePhase, now: Date, lapSeconds: Double, length: Double) -> TraceFrame? {
        func elapsed(_ from: Date) -> Double { max(0, now.timeIntervalSince(from)) }
        func head(_ since: Date) -> Double {
            (elapsed(since) / lapSeconds).truncatingRemainder(dividingBy: 1)
        }

        switch phase {
        case .off:
            return nil

        case .racing(let since):
            let intensity = min(1, elapsed(since) / TraceTiming.fadeIn)
            return TraceFrame(head: head(since), length: length, intensity: intensity, pulse: 0)

        case .finishing(let since, let at):
            let t = elapsed(at)
            let close = min(1, t / TraceTiming.closeLoop)
            let eased = 1 - pow(1 - close, 3)
            let afterClose = t - TraceTiming.closeLoop
            let pulse = (0..<TraceTiming.pulse).contains(afterClose)
                ? sin(.pi * afterClose / TraceTiming.pulse) : 0
            let fadeT = afterClose - TraceTiming.pulse
            let intensity = fadeT <= 0 ? 1 : max(0, 1 - fadeT / TraceTiming.finishFade)
            return TraceFrame(
                head: head(since), length: length + (1 - length) * eased,
                intensity: intensity, pulse: pulse)

        case .fading(let since, let at):
            let intensity = max(0, 1 - elapsed(at) / TraceTiming.exitFade)
            return TraceFrame(head: head(since), length: length, intensity: intensity, pulse: 0)
        }
    }

    /// 3s per 1000pt of perimeter at speed 1, so the head moves at the same
    /// pace in every pane. Never below 0.25s, so tiny panes stay finite.
    static func lapSeconds(perimeter: Double, speed: Double) -> Double {
        max(0.25, 3 * (perimeter / 1000) / speed)
    }
}
#endif
