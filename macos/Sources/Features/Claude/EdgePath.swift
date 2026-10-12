#if os(macOS)
import SwiftUI

/// A pane's right inside edge as one shuttle loop, in SwiftUI coordinates
/// (y grows down): down from the top-right corner to the bottom-right, then
/// back up the same line. Fractions of the round trip wrap, so any real
/// number is a valid position, and a tail that runs past a turnaround
/// doubles back along the edge.
struct EdgePath {
    struct Sample: Equatable {
        var point: CGPoint
        /// Direction of travel (unit vector).
        var tangent: CGVector
        /// Points into the pane (unit vector).
        var normal: CGVector
    }

    let rect: CGRect

    /// One round trip: down the right edge and back up.
    var loopLength: Double { 2 * Double(rect.height) }

    init(size: CGSize, inset: CGFloat) {
        let width = max(0, size.width - 2 * inset)
        let height = max(0, size.height - 2 * inset)
        // Degenerate panes collapse to a point so every sample stays finite.
        if width == 0 || height == 0 {
            rect = CGRect(x: inset, y: inset, width: 0, height: 0)
        } else {
            rect = CGRect(x: inset, y: inset, width: width, height: height)
        }
    }

    func sample(at fraction: Double) -> Sample {
        let normal = CGVector(dx: -1, dy: 0)
        let total = loopLength
        guard total > 0 else {
            return Sample(point: rect.origin, tangent: CGVector(dx: 0, dy: 1), normal: normal)
        }
        var wrapped = fraction.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        let d = CGFloat(wrapped * total)
        let h = rect.height
        if d < h {
            return Sample(point: CGPoint(x: rect.maxX, y: rect.minY + d),
                          tangent: CGVector(dx: 0, dy: 1), normal: normal)
        }
        return Sample(point: CGPoint(x: rect.maxX, y: rect.maxY - (d - h)),
                      tangent: CGVector(dx: 0, dy: -1), normal: normal)
    }

    /// Maps a lap position (0..<1 of the lap's time) to a place on the edge.
    /// Each leg (down, then up) takes half the lap. Along a leg the speed is
    /// a sine: the head leaves the end at rest, is fastest mid-edge, and
    /// comes to rest again at the other end.
    func easedFraction(_ lap: Double) -> Double {
        var wrapped = lap.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        let leg = min(1, Int(wrapped * 2))
        let u = wrapped * 2 - Double(leg)
        let eased = (1 - cos(.pi * u)) / 2
        return (Double(leg) + eased) / 2
    }

    /// The point `inward` points into the pane from the edge at `fraction`.
    func offsetPoint(at fraction: Double, inward: CGFloat) -> CGPoint {
        let s = sample(at: fraction)
        return CGPoint(x: s.point.x + s.normal.dx * inward, y: s.point.y + s.normal.dy * inward)
    }

    /// The edge between two fractions (`to` ≥ `from`), as a polyline with
    /// ~3pt resolution and the turnarounds it passes included.
    func segment(from: Double, to: Double) -> Path {
        var path = Path()
        let span = max(0, to - from)
        guard loopLength > 0, span > 0 else { return path }
        let steps = min(800, max(2, Int(span * loopLength / 3)))
        for i in 0...steps {
            let point = sample(at: from + span * Double(i) / Double(steps)).point
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// The whole right edge, top to bottom.
    var line: Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
#endif
