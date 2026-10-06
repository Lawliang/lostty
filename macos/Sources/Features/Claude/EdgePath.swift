#if os(macOS)
import SwiftUI

/// A pane's inside edge as one clockwise loop starting at the top-left
/// corner, in SwiftUI coordinates (y grows down). Fractions of the
/// perimeter wrap, so any real number is a valid position.
struct EdgePath {
    struct Sample: Equatable {
        var point: CGPoint
        /// Direction of travel (unit vector).
        var tangent: CGVector
        /// Points into the pane (unit vector).
        var normal: CGVector
    }

    let rect: CGRect

    var perimeter: Double { 2 * Double(rect.width + rect.height) }

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
        let total = perimeter
        guard total > 0 else {
            return Sample(point: rect.origin, tangent: CGVector(dx: 1, dy: 0), normal: CGVector(dx: 0, dy: 1))
        }
        var wrapped = fraction.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        var d = CGFloat(wrapped * total)
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

    /// The point `inward` points into the pane from the edge at `fraction`.
    func offsetPoint(at fraction: Double, inward: CGFloat) -> CGPoint {
        let s = sample(at: fraction)
        return CGPoint(x: s.point.x + s.normal.dx * inward, y: s.point.y + s.normal.dy * inward)
    }

    /// The edge between two fractions (`to` ≥ `from`), as a polyline with
    /// ~3pt resolution and the corners it passes included.
    func segment(from: Double, to: Double) -> Path {
        var path = Path()
        let span = max(0, to - from)
        guard perimeter > 0, span > 0 else { return path }
        let steps = min(800, max(2, Int(span * perimeter / 3)))
        for i in 0...steps {
            let point = sample(at: from + span * Double(i) / Double(steps)).point
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// The whole loop.
    var outline: Path { Path(rect) }
}
#endif
