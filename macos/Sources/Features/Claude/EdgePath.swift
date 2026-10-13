import SwiftUI

/// The stretch of a pane's inside edge the trace's head has travelled
/// (TraceMotion.path), as straight runs in SwiftUI coordinates (y grows
/// down) ending at the head. Fractions run from 0, the oldest point, to 1,
/// the head, and clamp outside that.
struct EdgePath {
    struct Sample: Equatable {
        var point: CGPoint
        /// Direction of travel (unit vector).
        var tangent: CGVector
        /// Points into the pane (unit vector).
        var normal: CGVector
    }

    /// One straight piece along a side. `tangent` and `normal` are given
    /// rather than derived so a zero-length piece still has a direction.
    struct Run: Equatable {
        var from: CGPoint
        var to: CGPoint
        var tangent: CGVector
        var normal: CGVector

        var length: Double { Double(hypot(to.x - from.x, to.y - from.y)) }
    }

    let runs: [Run]
    /// Total length in points.
    let length: Double

    init(runs: [Run]) {
        self.runs = runs
        length = runs.reduce(0) { $0 + $1.length }
    }

    func sample(at fraction: Double) -> Sample {
        guard let first = runs.first else {
            return Sample(point: .zero, tangent: CGVector(dx: 1, dy: 0), normal: CGVector(dx: 0, dy: 1))
        }
        var d = min(1, max(0, fraction)) * length
        for run in runs {
            let l = run.length
            if d <= l, l > 0 {
                let t = CGFloat(d / l)
                return Sample(point: CGPoint(x: run.from.x + (run.to.x - run.from.x) * t,
                                             y: run.from.y + (run.to.y - run.from.y) * t),
                              tangent: run.tangent, normal: run.normal)
            }
            d -= l
        }
        let last = runs.last { $0.length > 0 } ?? first
        let end = runs.last ?? first
        return Sample(point: end.to, tangent: last.tangent, normal: last.normal)
    }

    /// The point `inward` points into the pane from the edge at `fraction`.
    func offsetPoint(at fraction: Double, inward: CGFloat) -> CGPoint {
        let s = sample(at: fraction)
        return CGPoint(x: s.point.x + s.normal.dx * inward, y: s.point.y + s.normal.dy * inward)
    }

    /// The edge between two fractions, as a polyline with ~3pt resolution
    /// and the corners and turnarounds it passes included.
    func segment(from: Double, to: Double) -> Path {
        var path = Path()
        let a = min(1, max(0, from)), b = min(1, max(0, to))
        let span = b - a
        guard length > 0, span > 0 else { return path }
        let steps = min(800, max(2, Int(span * length / 3)))
        for i in 0...steps {
            let point = sample(at: a + span * Double(i) / Double(steps)).point
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
