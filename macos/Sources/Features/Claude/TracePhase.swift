#if os(macOS)
import Foundation

/// Trace animation timings (spec §4).
enum TraceTiming {
    static let fadeIn: TimeInterval = 0.2
}

/// One pane's trace: racing while Claude works, gone the moment it stops.
enum TracePhase: Equatable {
    case off
    case racing(since: Date)

    var isOff: Bool { self == .off }

    func applying(_ state: ClaudeState, now: Date) -> TracePhase {
        switch (state, self) {
        case (.busy, .off): .racing(since: now)
        case (.busy, .racing): self
        case (.idle, _), (.exit, _): .off
        }
    }
}

/// What to draw at one instant. Positions are fractions of the route's loop
/// (`EdgePath`).
struct TraceFrame: Equatable {
    /// Head position, 0..<1.
    var head: Double
    /// Tail length, 0...1.
    var length: Double
    /// Overall opacity, 0...1.
    var intensity: Double

    static func make(_ phase: TracePhase, now: Date, lapSeconds: Double, length: Double) -> TraceFrame? {
        guard case .racing(let since) = phase else { return nil }
        let elapsed = max(0, now.timeIntervalSince(since))
        return TraceFrame(
            head: (elapsed / lapSeconds).truncatingRemainder(dividingBy: 1),
            length: length,
            intensity: min(1, elapsed / TraceTiming.fadeIn))
    }

    /// Seconds the head spends on each leg (a side of the border, or one way
    /// along a single side) at `speed = 1`, whatever its length, so the ease
    /// into and out of each corner or turnaround is always long enough to see.
    static let secondsPerLeg: Double = 0.6

    static func lapSeconds(speed: Double, legs: Int) -> Double {
        Double(legs) * secondsPerLeg / speed
    }
}
#endif
