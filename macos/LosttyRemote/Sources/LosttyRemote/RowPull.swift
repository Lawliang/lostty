import Foundation

/// Dragging a list row left to refresh that terminal, like pull to refresh
/// turned sideways. Distances are points; `dx` is the drag's horizontal
/// travel, negative to the left.
public enum RowPull {
    /// Letting go at least this far left refreshes.
    public static let threshold: Double = 72
    /// The row slides at most this far, however far the finger goes.
    public static let limit: Double = 96

    /// A drag that is mostly leftward is a pull; anything steeper is the
    /// list scrolling, and rightward has nothing to reveal.
    public static func isSideways(dx: Double, dy: Double) -> Bool {
        dx < 0 && abs(dx) > abs(dy) * 1.5
    }

    public static func refreshes(dx: Double) -> Bool {
        -dx >= threshold
    }

    /// How full the refresh arrow is: 1 once letting go would refresh.
    public static func progress(dx: Double) -> Double {
        min(1, max(0, -dx) / threshold)
    }

    /// Where the row sits: behind the finger, easing off toward `limit`.
    public static func offset(dx: Double) -> Double {
        let pull = max(0, -dx)
        return -limit * (1 - exp(-pull / limit))
    }
}
