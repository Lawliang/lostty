#if os(macOS)
import SwiftUI

/// The part of a pane's inside edge a trace travels, as one loop in
/// SwiftUI coordinates (y grows down). For `.all` it is the whole border,
/// clockwise from the top-left corner. For one side it is a shuttle: along
/// the side (top to bottom, or left to right), then back the same way.
/// Fractions of the loop wrap, so any real number is a valid position, and
/// a tail that runs past a shuttle's turnaround doubles back along the side.
struct EdgePath {
    struct Sample: Equatable {
        var point: CGPoint
        /// Direction of travel (unit vector).
        var tangent: CGVector
        /// Points into the pane (unit vector).
        var normal: CGVector
    }

    let rect: CGRect
    let route: TraceRoute

    init(size: CGSize, inset: CGFloat, route: TraceRoute) {
        self.route = route
        let width = max(0, size.width - 2 * inset)
        let height = max(0, size.height - 2 * inset)
        // Degenerate panes collapse to a point so every sample stays finite.
        if width == 0 || height == 0 {
            rect = CGRect(x: inset, y: inset, width: 0, height: 0)
        } else {
            rect = CGRect(x: inset, y: inset, width: width, height: height)
        }
    }

    /// The straight runs the head travels in one lap, in order. Each takes
    /// the same time, eased to rest at both ends.
    var legs: [Double] {
        let w = Double(rect.width), h = Double(rect.height)
        switch route {
        case .all: return [w, h, w, h]
        case .top, .bottom: return [w, w]
        case .left, .right: return [h, h]
        }
    }

    var loopLength: Double { legs.reduce(0, +) }

    /// One side's start, end and inward normal, for the shuttle routes.
    private var side: (start: CGPoint, end: CGPoint, normal: CGVector) {
        switch route {
        case .all, .right:
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: -1, dy: 0))
        case .top:
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 0, dy: 1))
        case .bottom:
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 0, dy: -1))
        case .left:
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 1, dy: 0))
        }
    }

    func sample(at fraction: Double) -> Sample {
        let total = loopLength
        guard total > 0 else {
            return Sample(point: rect.origin, tangent: CGVector(dx: 1, dy: 0), normal: CGVector(dx: 0, dy: 1))
        }
        var wrapped = fraction.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        let d = CGFloat(wrapped * total)
        return route == .all ? sampleBorder(d) : sampleSide(d)
    }

    private func sampleBorder(_ distance: CGFloat) -> Sample {
        var d = distance
        let w = rect.width, h = rect.height
        if d < w {
            return Sample(point: CGPoint(x: rect.minX + d, y: rect.minY),
                          tangent: CGVector(dx: 1, dy: 0), normal: CGVector(dx: 0, dy: 1))
        }
        d -= w
        if d < h {
            return Sample(point: CGPoint(x: rect.maxX, y: rect.minY + d),
                          tangent: CGVector(dx: 0, dy: 1), normal: CGVector(dx: -1, dy: 0))
        }
        d -= h
        if d < w {
            return Sample(point: CGPoint(x: rect.maxX - d, y: rect.maxY),
                          tangent: CGVector(dx: -1, dy: 0), normal: CGVector(dx: 0, dy: -1))
        }
        d -= w
        return Sample(point: CGPoint(x: rect.minX, y: rect.maxY - d),
                      tangent: CGVector(dx: 0, dy: -1), normal: CGVector(dx: 1, dy: 0))
    }

    private func sampleSide(_ distance: CGFloat) -> Sample {
        let (start, end, normal) = side
        let length = CGFloat(legs[0])
        let dir = CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
        if distance < length {
            return Sample(point: CGPoint(x: start.x + dir.dx * distance, y: start.y + dir.dy * distance),
                          tangent: dir, normal: normal)
        }
        let back = distance - length
        return Sample(point: CGPoint(x: end.x - dir.dx * back, y: end.y - dir.dy * back),
                      tangent: CGVector(dx: -dir.dx, dy: -dir.dy), normal: normal)
    }

    /// Maps a lap position (0..<1 of the lap's time) to a place on the loop.
    /// Each leg takes an equal share of the lap. Along a leg the speed is a
    /// sine: the head leaves the corner or end at rest, is fastest midway,
    /// and comes to rest again at the next one.
    func easedFraction(_ lap: Double) -> Double {
        let lengths = legs
        let total = loopLength
        guard total > 0 else { return lap }
        var wrapped = lap.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        let count = lengths.count
        let leg = min(count - 1, Int(wrapped * Double(count)))
        let u = wrapped * Double(count) - Double(leg)
        let start = lengths[..<leg].reduce(0, +)
        let eased = (1 - cos(.pi * u)) / 2
        return (start + eased * lengths[leg]) / total
    }

    /// The point `inward` points into the pane from the edge at `fraction`.
    func offsetPoint(at fraction: Double, inward: CGFloat) -> CGPoint {
        let s = sample(at: fraction)
        return CGPoint(x: s.point.x + s.normal.dx * inward, y: s.point.y + s.normal.dy * inward)
    }

    /// The edge between two fractions (`to` ≥ `from`), as a polyline with
    /// ~3pt resolution and the corners and turnarounds it passes included.
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

    /// Everything the route covers: the whole border, or the one side.
    var outline: Path {
        guard route != .all else { return Path(rect) }
        var path = Path()
        path.move(to: side.start)
        path.addLine(to: side.end)
        return path
    }
}
#endif
