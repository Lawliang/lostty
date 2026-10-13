import SwiftUI

/// The approved chibi axolotl (docs/superpowers/specs/assets/lostty-chibi-axolotl.svg),
/// drawn in a 100×100 box with y down.
enum AxolotlGeometry {
    /// One gill petal: an ellipse centred at (x, y), turned by `rotation` degrees.
    struct Petal: Equatable {
        var x: CGFloat
        var y: CGFloat
        var rx: CGFloat
        var ry: CGFloat
        var rotation: CGFloat
    }

    static let leftGills: [Petal] = [
        Petal(x: 14, y: 21, rx: 9, ry: 4.6, rotation: -42),
        Petal(x: 9, y: 34, rx: 9, ry: 4.6, rotation: -12),
        Petal(x: 11, y: 47, rx: 8.5, ry: 4.3, rotation: 18),
    ]

    /// The right side mirrors the left.
    static func gills(_ side: AxolotlSide) -> [Petal] {
        switch side {
        case .left: leftGills
        case .right: leftGills.map { Petal(x: 100 - $0.x, y: $0.y, rx: $0.rx, ry: $0.ry, rotation: -$0.rotation) }
        }
    }

    /// Where each side's gills meet the head, as a unit point for swaying them.
    static func gillAnchor(_ side: AxolotlSide) -> UnitPoint {
        side == .left ? UnitPoint(x: 0.20, y: 0.34) : UnitPoint(x: 0.80, y: 0.34)
    }

    /// The waving pose's raised arm (its own right, on the viewer's left):
    /// from the shoulder up past the cheek to the hand.
    static let shoulder = CGPoint(x: 37, y: 73)
    static let hand = CGPoint(x: 12, y: 40)
    static let armWidth: CGFloat = 7
    static let handRadius: CGFloat = 5.4

    /// Where the tail meets the body, as a unit point, for wagging it.
    static let tailAnchor = UnitPoint(x: 0.61, y: 0.8)

    /// The shoulder as a unit point, for swinging the arm.
    static var shoulderAnchor: UnitPoint { UnitPoint(x: shoulder.x / 100, y: shoulder.y / 100) }

    static let skin = Color(losttyHex: 0xF7B2D8)
    static let shade = Color(losttyHex: 0xEC97C6)
    static let ink = Color(losttyHex: 0x3A1530)
}

enum AxolotlSide { case left, right }

private extension Path {
    /// Scales a path drawn in the 100-unit box into `rect`.
    func fitted(to rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        return applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
    }

    static func unitEllipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotation: CGFloat = 0) -> Path {
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            .applying(CGAffineTransform(rotationAngle: rotation * .pi / 180)
                .concatenating(CGAffineTransform(translationX: x, y: y)))
    }
}

/// One filled part of the chibi; each part is a single colour.
struct AxolotlPart: Shape {
    /// `limbsWaving`: the limbs less the arm the waving pose raises.
    enum Kind { case tail, body, belly, limbs, limbsWaving, gills(AxolotlSide), head, highlight, blush }

    var kind: Kind

    func path(in rect: CGRect) -> Path { Self.unitPath(kind).fitted(to: rect) }

    static func unitPath(_ kind: Kind) -> Path {
        switch kind {
        case .tail:
            var path = Path()
            path.move(to: CGPoint(x: 60, y: 82))
            path.addCurve(to: CGPoint(x: 84, y: 76), control1: CGPoint(x: 70, y: 86), control2: CGPoint(x: 80, y: 84))
            path.addCurve(to: CGPoint(x: 80, y: 73), control1: CGPoint(x: 86, y: 72), control2: CGPoint(x: 82, y: 70))
            path.addCurve(to: CGPoint(x: 63, y: 76), control1: CGPoint(x: 77, y: 78), control2: CGPoint(x: 70, y: 79))
            path.closeSubpath()
            return path
        case .body:
            return .unitEllipse(50, 76, 15, 12)
        case .belly:
            return .unitEllipse(50, 79, 8, 6)
        case .limbs, .limbsWaving:
            var path = Path()
            var limbs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(39, 80, 4.2, 3.2), (61, 80, 4.2, 3.2), (43, 88, 5, 3), (57, 88, 5, 3)]
            if case .limbsWaving = kind { limbs.removeFirst() }
            for (x, y, rx, ry) in limbs { path.addPath(.unitEllipse(x, y, rx, ry)) }
            return path
        case .gills(let side):
            var path = Path()
            for petal in AxolotlGeometry.gills(side) {
                path.addPath(.unitEllipse(petal.x, petal.y, petal.rx, petal.ry, rotation: petal.rotation))
            }
            return path
        case .head:
            // A soft rounded square: flatter on top than an ellipse.
            var path = Path()
            path.move(to: CGPoint(x: 50, y: 15))
            path.addCurve(to: CGPoint(x: 83, y: 42.3), control1: CGPoint(x: 76.4, y: 15), control2: CGPoint(x: 83, y: 26.7))
            path.addCurve(to: CGPoint(x: 50, y: 67), control1: CGPoint(x: 83, y: 60.5), control2: CGPoint(x: 69.8, y: 67))
            path.addCurve(to: CGPoint(x: 17, y: 42.3), control1: CGPoint(x: 30.2, y: 67), control2: CGPoint(x: 17, y: 60.5))
            path.addCurve(to: CGPoint(x: 50, y: 15), control1: CGPoint(x: 17, y: 26.7), control2: CGPoint(x: 23.6, y: 15))
            path.closeSubpath()
            return path
        case .highlight:
            return .unitEllipse(34, 24, 7, 3.2, rotation: -18)
        case .blush:
            var path = Path()
            path.addPath(.unitEllipse(26, 55, 5, 3))
            path.addPath(.unitEllipse(75, 55, 5, 3))
            return path
        }
    }
}

/// The waving pose's raised arm, in parts: the arm, the hand, and two
/// little wave marks beyond the hand.
struct AxolotlRaisedArm: Shape {
    enum Part { case arm, hand, marks }

    var part: Part

    func path(in rect: CGRect) -> Path { Self.unitPath(part).fitted(to: rect) }

    static func unitPath(_ part: Part) -> Path {
        let from = AxolotlGeometry.shoulder
        let to = AxolotlGeometry.hand
        let angle = atan2(to.y - from.y, to.x - from.x)
        switch part {
        case .arm:
            let length = hypot(to.x - from.x, to.y - from.y)
            let width = AxolotlGeometry.armWidth
            return Path(roundedRect: CGRect(x: 0, y: -width / 2, width: length, height: width), cornerRadius: width / 2)
                .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: from.x, y: from.y)))
        case .hand:
            let r = AxolotlGeometry.handRadius
            return Path(ellipseIn: CGRect(x: to.x - r, y: to.y - r, width: r * 2, height: r * 2))
        case .marks:
            var path = Path()
            for radius: CGFloat in [8, 11] {
                // Each mark its own stroke: no line joining one to the next.
                path.move(to: CGPoint(x: to.x + radius * cos(angle - 0.45), y: to.y + radius * sin(angle - 0.45)))
                path.addArc(center: to, radius: radius, startAngle: .radians(angle - 0.45),
                            endAngle: .radians(angle + 0.45), clockwise: false)
            }
            return path
        }
    }
}

/// The icon's prompt eyes: ">" and a "—" that blinks like a cursor.
struct AxolotlEyes: Shape {
    var cursorVisible = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 33, y: 36))
        path.addLine(to: CGPoint(x: 42, y: 43))
        path.addLine(to: CGPoint(x: 33, y: 50))
        if cursorVisible {
            path.move(to: CGPoint(x: 56, y: 43))
            path.addLine(to: CGPoint(x: 68, y: 43))
        }
        return path.fitted(to: rect)
    }
}

/// Eyes shut in sleep: two soft arcs where the prompt eyes would be.
struct AxolotlSleepingEyes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 32, y: 42))
        path.addQuadCurve(to: CGPoint(x: 43, y: 42), control: CGPoint(x: 37.5, y: 48))
        path.move(to: CGPoint(x: 56, y: 42))
        path.addQuadCurve(to: CGPoint(x: 68, y: 42), control: CGPoint(x: 62, y: 48))
        return path.fitted(to: rect)
    }
}

/// A small "w" mouth.
struct AxolotlMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 46, y: 53))
        path.addQuadCurve(to: CGPoint(x: 50, y: 53.5), control: CGPoint(x: 48, y: 56))
        path.addQuadCurve(to: CGPoint(x: 54, y: 53), control: CGPoint(x: 52, y: 56))
        return path.fitted(to: rect)
    }
}

/// The check the happy pose shows above its head (top right would sit on
/// the gills).
struct AxolotlCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 44, y: 7))
        path.addLine(to: CGPoint(x: 49, y: 12))
        path.addLine(to: CGPoint(x: 58, y: 2.5))
        return path.fitted(to: rect)
    }
}
