import Foundation

/// Trace animation timings (spec §4).
enum TraceTiming {
    static let fadeIn: TimeInterval = 0.2
}

/// What to draw at one instant, along the `EdgePath` the head has
/// travelled. Positions are fractions of that path; the head is at its end.
struct TraceFrame: Equatable {
    /// Head position, 0...1.
    var head: Double
    /// Tail length, 0...1.
    var length: Double
    /// Overall opacity, 0...1.
    var intensity: Double

    /// Fades in over `TraceTiming.fadeIn` from the trace's start.
    static func intensity(elapsed: TimeInterval) -> Double {
        min(1, max(0, elapsed) / TraceTiming.fadeIn)
    }

    /// Seconds the head spends on each leg (one side of the pane, corner to
    /// corner) at `speed = 1`, whatever its length, so the ease into and out
    /// of each corner is always long enough to see.
    static let secondsPerLeg: Double = 0.6

    static func legSeconds(speed: Double) -> Double {
        secondsPerLeg / speed
    }
}
