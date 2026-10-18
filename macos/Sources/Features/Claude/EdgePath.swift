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
    /// A window's rounded corners: points in a corner of `rect` bend onto
    /// its arc of `radius`, so the head never leaves the window.
    var rounding: (rect: CGRect, radius: CGFloat)?

    init(runs: [Run], rounding: (rect: CGRect, radius: CGFloat)? = nil) {
        self.runs = runs
        self.rounding = rounding
        length = runs.reduce(0) { $0 + $1.length }
    }

    /// `point` bent onto the arc of the rounded `rect`'s corner it falls
    /// in; points along the straight stretches of the sides are kept.
    static func bend(_ point: CGPoint, in rect: CGRect, radius: CGFloat) -> CGPoint {
        let r = min(radius, rect.width / 2, rect.height / 2)
        guard r > 0 else { return point }
        let center = CGPoint(x: min(max(point.x, rect.minX + r), rect.maxX - r),
                             y: min(max(point.y, rect.minY + r), rect.maxY - r))
        guard center.x != point.x, center.y != point.y else { return point }
        let dx = point.x - center.x, dy = point.y - center.y
        let d = hypot(dx, dy)
        return CGPoint(x: center.x + dx / d * r, y: center.y + dy / d * r)
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
                return Sample(point: bent(CGPoint(x: run.from.x + (run.to.x - run.from.x) * t,
                                                  y: run.from.y + (run.to.y - run.from.y) * t)),
                              tangent: run.tangent, normal: run.normal)
            }
            d -= l
        }
        let last = runs.last { $0.length > 0 } ?? first
        let end = runs.last ?? first
        return Sample(point: bent(end.to), tangent: last.tangent, normal: last.normal)
    }

    private func bent(_ point: CGPoint) -> CGPoint {
        guard let rounding else { return point }
        return Self.bend(point, in: rounding.rect, radius: rounding.radius)
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
