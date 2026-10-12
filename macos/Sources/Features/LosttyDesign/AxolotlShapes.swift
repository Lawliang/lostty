import SwiftUI

/// The approved axolotl, drawn in a 100×100 box with y down. White
/// line-art; the gill feathers are the only magenta.
enum AxolotlGeometry {
    /// Gill stalks on the left side: (start, control, end). The right side
    /// mirrors them.
    static let leftStalks: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 24, y: 38), CGPoint(x: 16, y: 30), CGPoint(x: 9, y: 26)),
        (CGPoint(x: 19, y: 47), CGPoint(x: 11, y: 45), CGPoint(x: 4, y: 46)),
        (CGPoint(x: 21, y: 57), CGPoint(x: 13, y: 61), CGPoint(x: 8, y: 66)),
    ]

    static func stalks(_ side: AxolotlSide) -> [(CGPoint, CGPoint, CGPoint)] {
        switch side {
        case .left: leftStalks
        case .right: leftStalks.map { a, b, c in
            (CGPoint(x: 100 - a.x, y: a.y), CGPoint(x: 100 - b.x, y: b.y), CGPoint(x: 100 - c.x, y: c.y))
        }
        }
    }

    /// Where each side's gills meet the head, as a unit point for rotating them.
    static func gillAnchor(_ side: AxolotlSide) -> UnitPoint {
        side == .left ? UnitPoint(x: 0.21, y: 0.48) : UnitPoint(x: 0.79, y: 0.48)
    }
}

enum AxolotlSide { case left, right }

/// Maps the 100×100 drawing box into `rect`.
private struct Box {
    let rect: CGRect
    var scale: CGFloat { min(rect.width, rect.height) / 100 }
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
}

/// Head, body, legs, tail and mouth.
struct AxolotlBody: Shape {
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        // Head: wide, soft, slightly flat on top.
        path.move(to: b.p(50, 27))
        path.addCurve(to: b.p(82, 50), control1: b.p(70, 27), control2: b.p(82, 36))
        path.addCurve(to: b.p(50, 71), control1: b.p(82, 64), control2: b.p(68, 71))
        path.addCurve(to: b.p(18, 50), control1: b.p(32, 71), control2: b.p(18, 64))
        path.addCurve(to: b.p(50, 27), control1: b.p(18, 36), control2: b.p(30, 27))
        // Body: a soft bean under the head, with stubby front legs.
        path.move(to: b.p(39, 69))
        path.addCurve(to: b.p(50, 88), control1: b.p(34, 78), control2: b.p(40, 88))
        path.addCurve(to: b.p(61, 69), control1: b.p(60, 88), control2: b.p(66, 78))
        path.move(to: b.p(41, 82)); path.addQuadCurve(to: b.p(35, 89), control: b.p(37, 84))
        path.move(to: b.p(59, 82)); path.addQuadCurve(to: b.p(65, 89), control: b.p(63, 84))
        // Tail curling right.
        path.move(to: b.p(60, 82))
        path.addCurve(to: b.p(84, 84), control1: b.p(68, 90), control2: b.p(80, 90))
        path.addCurve(to: b.p(80, 74), control1: b.p(87, 80), control2: b.p(85, 74))
        // Mouth: a wide, small smile.
        path.move(to: b.p(43, 60))
        path.addQuadCurve(to: b.p(57, 60), control: b.p(50, 64))
        return path
    }
}

/// One side's three gill stalks (white).
struct AxolotlStalks: Shape {
    var side: AxolotlSide
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        for (a, c1, c) in AxolotlGeometry.stalks(side) {
            path.move(to: b.p(a.x, a.y))
            path.addQuadCurve(to: b.p(c.x, c.y), control: b.p(c1.x, c1.y))
        }
        return path
    }
}

/// One side's gill feathers: short strokes angled back toward the head,
/// like fletching (magenta).
struct AxolotlFronds: Shape {
    var side: AxolotlSide
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        for (a, c1, c) in AxolotlGeometry.stalks(side) {
            for t in [0.38, 0.62, 0.86] as [CGFloat] {
                let x = (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * c1.x + t * t * c.x
                let y = (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * c1.y + t * t * c.y
                let dx = 2 * (1 - t) * (c1.x - a.x) + 2 * t * (c.x - c1.x)
                let dy = 2 * (1 - t) * (c1.y - a.y) + 2 * t * (c.y - c1.y)
                let length = max(0.001, (dx * dx + dy * dy).squareRoot())
                let tx = dx / length, ty = dy / length, nx = -ty, ny = tx
                for sign in [1.0, -1.0] as [CGFloat] {
                    path.move(to: b.p(x, y))
                    path.addLine(to: b.p(x + (-tx * 0.45 + nx * sign * 0.9) * 4.2,
                                         y + (-ty * 0.45 + ny * sign * 0.9) * 4.2))
                }
            }
        }
        return path
    }
}

/// The icon's prompt eyes: ">" and a "—" that blinks like a cursor.
struct AxolotlEyes: Shape {
    var cursorVisible = true
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        path.move(to: b.p(33, 43)); path.addLine(to: b.p(40, 48)); path.addLine(to: b.p(33, 53))
        if cursorVisible {
            path.move(to: b.p(58, 48)); path.addLine(to: b.p(67, 48))
        }
        return path
    }
}

/// The small check the happy pose holds up, top right.
struct AxolotlCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let b = Box(rect: rect)
        var path = Path()
        path.move(to: b.p(80, 14)); path.addLine(to: b.p(85, 19)); path.addLine(to: b.p(95, 7))
        return path
    }
}
