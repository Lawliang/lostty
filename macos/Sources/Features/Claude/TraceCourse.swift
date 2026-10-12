#if os(macOS)
import SwiftUI

/// A corner of a pane's inside edge.
enum Corner: CaseIterable {
    case topLeft, topRight, bottomRight, bottomLeft

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        }
    }

    var clockwiseNext: Corner {
        switch self {
        case .topLeft: .topRight
        case .topRight: .bottomRight
        case .bottomRight: .bottomLeft
        case .bottomLeft: .topLeft
        }
    }

    /// The two corners that share a side with this one.
    var neighbors: [Corner] {
        Corner.allCases.filter { $0 != self && $0 != clockwiseNext.clockwiseNext }
    }

    /// Unit vector into the pane from the side between two neighboring
    /// corners.
    static func inwardNormal(_ a: Corner, _ b: Corner) -> CGVector {
        switch Set([a, b]) {
        case [.topLeft, .topRight]: CGVector(dx: 0, dy: 1)
        case [.topRight, .bottomRight]: CGVector(dx: -1, dy: 0)
        case [.bottomRight, .bottomLeft]: CGVector(dx: 0, dy: -1)
        default: CGVector(dx: 1, dy: 0)
        }
    }
}

/// Where the head runs: the person's route while Claude works, or back and
/// forth along the bottom edge while only its subagents do.
enum TraceCourse: Equatable {
    case route(TraceRoute)
    case subagents

    /// The corners the course runs between, the first one where a fresh
    /// trace starts.
    var corners: [Corner] {
        switch self {
        case .route(.all): [.topLeft, .topRight, .bottomRight, .bottomLeft]
        case .route(.right): [.topRight, .bottomRight]
        case .route(.top): [.topLeft, .topRight]
        case .route(.left): [.topLeft, .bottomLeft]
        case .subagents: [.bottomRight, .bottomLeft]
        }
    }

    /// The corner the head heads for from `corner`. On the course, it keeps
    /// going: clockwise all around, or back along its side. Off it (the
    /// course just changed), it takes the side that leads onto the course.
    func next(after corner: Corner) -> Corner {
        let corners = corners
        guard corners.contains(corner) else {
            return corner.neighbors.first(where: corners.contains) ?? corners[0]
        }
        if self == .route(.all) { return corner.clockwiseNext }
        return corners.first { $0 != corner } ?? corner
    }

    /// One full lap's length, for sizing the tail.
    func lapLength(in rect: CGRect) -> Double {
        let w = Double(rect.width), h = Double(rect.height)
        switch self {
        case .route(.all): return 2 * (w + h)
        case .route(.right), .route(.left): return 2 * h
        case .route(.top), .subagents: return 2 * w
        }
    }

    /// Everything the course covers, for the Reduce Motion glow.
    func outline(in rect: CGRect) -> Path {
        guard self != .route(.all) else { return Path(rect) }
        var path = Path()
        path.move(to: corners[0].point(in: rect))
        path.addLine(to: corners[1].point(in: rect))
        return path
    }
}

/// The head's journey since the trace started: legs from corner to corner,
/// each taking the same time and eased to rest at both ends. A leg's end
/// picks the next from the course at that moment, so a course change waits
/// for the head to finish the side it is on.
struct TraceMotion: Equatable {
    struct Leg: Equatable {
        var from: Corner
        var to: Corner
        /// Seconds since the trace started.
        var start: Double
    }

    /// Enough history for the longest tail (half the border) to follow.
    static let keptLegs = 6

    private(set) var legs: [Leg] = []

    mutating func advance(to elapsed: Double, course: TraceCourse, legSeconds: Double) {
        if legs.isEmpty {
            let first = course.corners[0]
            legs = [Leg(from: first, to: course.next(after: first), start: 0)]
        }
        while let last = legs.last, elapsed >= last.start + legSeconds {
            legs.append(Leg(from: last.to, to: course.next(after: last.to), start: last.start + legSeconds))
            if legs.count > Self.keptLegs { legs.removeFirst() }
        }
    }

    /// The edge the head has travelled, ending at the head. Along a leg the
    /// speed is a sine: at rest leaving a corner, fastest midway, at rest
    /// again arriving at the next.
    func path(in rect: CGRect, at elapsed: Double, legSeconds: Double) -> EdgePath {
        var runs: [EdgePath.Run] = []
        for (i, leg) in legs.enumerated() {
            let from = leg.from.point(in: rect), to = leg.to.point(in: rect)
            var end = to
            if i == legs.count - 1 {
                let u = min(1, max(0, (elapsed - leg.start) / legSeconds))
                let eased = CGFloat((1 - cos(.pi * u)) / 2)
                end = CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
            }
            runs.append(EdgePath.Run(
                from: from, to: end, tangent: Self.direction(leg.from, leg.to),
                normal: Corner.inwardNormal(leg.from, leg.to)))
        }
        return EdgePath(runs: runs)
    }

    private static func direction(_ a: Corner, _ b: Corner) -> CGVector {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let p = a.point(in: unit), q = b.point(in: unit)
        return CGVector(dx: q.x - p.x, dy: q.y - p.y)
    }
}
#endif
