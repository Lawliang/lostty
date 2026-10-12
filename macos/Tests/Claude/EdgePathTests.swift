#if os(macOS)
import SwiftUI
import Testing
@testable import Ghostty

struct EdgePathTests {
    static let size = CGSize(width: 100, height: 50)

    // MARK: All around: 100x50 pane, inset 0 → perimeter 300. Top edge = 0..<1/3.

    let border = EdgePath(size: size, inset: 0, route: .all)

    @Test func borderLoopLength() {
        #expect(border.loopLength == 300)
        #expect(EdgePath(size: Self.size, inset: 5, route: .all).loopLength == 260)
    }

    @Test func borderWalksClockwiseFromTopLeft() {
        #expect(border.sample(at: 0).point == CGPoint(x: 0, y: 0))
        #expect(border.sample(at: 50.0 / 300).point == CGPoint(x: 50, y: 0))
        #expect(border.sample(at: 125.0 / 300).point == CGPoint(x: 100, y: 25))
        #expect(border.sample(at: 200.0 / 300).point == CGPoint(x: 50, y: 50))
        #expect(border.sample(at: 275.0 / 300).point == CGPoint(x: 0, y: 25))
    }

    @Test func borderTangentsAndInwardNormals() {
        let top = border.sample(at: 0.1)
        #expect(top.tangent == CGVector(dx: 1, dy: 0))
        #expect(top.normal == CGVector(dx: 0, dy: 1))
        let right = border.sample(at: 125.0 / 300)
        #expect(right.tangent == CGVector(dx: 0, dy: 1))
        #expect(right.normal == CGVector(dx: -1, dy: 0))
        #expect(border.sample(at: 200.0 / 300).normal == CGVector(dx: 0, dy: -1))
        #expect(border.sample(at: 275.0 / 300).normal == CGVector(dx: 1, dy: 0))
    }

    @Test func borderSegmentAcrossTheStartCorner() {
        let box = border.segment(from: -0.05, to: 0.05).boundingRect
        #expect(box.minX <= 0.001 && box.maxX >= 14.9)
        #expect(box.maxY >= 14.9)
    }

    // Each side takes a quarter of the lap whatever its length. Lap
    // positions 0, ¼, ½, ¾ are the corners.
    @Test func borderSidesEachTakeAQuarterOfTheLap() {
        #expect(border.legs.count == 4)
        #expect(abs(border.easedFraction(0) - 0) < 1e-9)
        #expect(abs(border.easedFraction(0.25) - 100.0 / 300) < 1e-9)
        #expect(abs(border.easedFraction(0.5) - 150.0 / 300) < 1e-9)
        #expect(abs(border.easedFraction(0.75) - 250.0 / 300) < 1e-9)
        // Halfway through a side's time is halfway along it.
        #expect(abs(border.easedFraction(0.125) - 50.0 / 300) < 1e-9)
        #expect(abs(border.easedFraction(0.375) - 125.0 / 300) < 1e-9)
    }

    @Test func borderOutlineIsTheRect() {
        #expect(border.outline.boundingRect == CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    // MARK: One side: a shuttle there and back. Right = 100 round trip,
    // top = 200.

    @Test(arguments: [
        (TraceRoute.right, 100.0, CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 50), CGVector(dx: -1, dy: 0)),
        (TraceRoute.left, 100.0, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 50), CGVector(dx: 1, dy: 0)),
        (TraceRoute.top, 200.0, CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGVector(dx: 0, dy: 1)),
        (TraceRoute.bottom, 200.0, CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50), CGVector(dx: 0, dy: -1)),
    ])
    func sideShuttlesThereAndBack(route: TraceRoute, loop: Double, start: CGPoint, end: CGPoint, normal: CGVector) {
        let path = EdgePath(size: Self.size, inset: 0, route: route)
        #expect(path.loopLength == loop)
        #expect(path.legs.count == 2)
        #expect(path.sample(at: 0).point == start)
        #expect(path.sample(at: 0.5).point == end)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        #expect(path.sample(at: 0.25).point == mid)
        #expect(path.sample(at: 0.75).point == mid)

        let out = path.sample(at: 0.2), back = path.sample(at: 0.7)
        #expect(back.tangent == CGVector(dx: -out.tangent.dx, dy: -out.tangent.dy))
        #expect(out.normal == normal && back.normal == normal)

        // Never strays off the side.
        let side = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        for i in 0..<200 {
            let p = path.sample(at: Double(i) / 200).point
            #expect(p.x >= side.minX && p.x <= side.maxX && p.y >= side.minY && p.y <= side.maxY)
        }
        #expect(path.outline.boundingRect == side)
    }

    @Test func sideSegmentFoldsBackAtTheTurnaround() {
        let right = EdgePath(size: Self.size, inset: 0, route: .right)
        let box = right.segment(from: 0.4, to: 0.6).boundingRect
        #expect(box.minX == 100 && box.maxX == 100)
        #expect(abs(box.minY - 40) < 0.001 && abs(box.maxY - 50) < 0.001)
    }

    @Test func sideLegsEachTakeHalfTheLap() {
        let right = EdgePath(size: Self.size, inset: 0, route: .right)
        #expect(abs(right.easedFraction(0) - 0) < 1e-9)
        #expect(abs(right.easedFraction(0.25) - 0.25) < 1e-9)
        #expect(abs(right.easedFraction(0.5) - 0.5) < 1e-9)
        #expect(abs(right.easedFraction(0.75) - 0.75) < 1e-9)
    }

    // MARK: Every route

    @Test(arguments: TraceRoute.allCases)
    func speedIsASineAlongEachLeg(route: TraceRoute) {
        let path = EdgePath(size: Self.size, inset: 0, route: route)
        let legs = Double(path.legs.count)
        // Speed along the first leg, in points per lap-fraction.
        func speed(at u: Double) -> Double {
            let du = 0.0005
            let a = path.easedFraction(u / legs), b = path.easedFraction((u + du) / legs)
            return (b - a) * path.loopLength / (du / legs)
        }
        let peak = speed(at: 0.5)
        #expect(speed(at: 0) / peak < 0.01)           // at rest leaving the corner
        #expect(speed(at: 0.9995) / peak < 0.01)      // at rest arriving at the next
        for u in stride(from: 0.1, through: 0.9, by: 0.1) {
            #expect(abs(speed(at: u) / peak - sin(.pi * u)) < 0.02)
        }
    }

    @Test(arguments: TraceRoute.allCases)
    func fractionsAndEasingWrap(route: TraceRoute) {
        let path = EdgePath(size: Self.size, inset: 0, route: route)
        #expect(path.sample(at: 1.25).point == path.sample(at: 0.25).point)
        #expect(path.sample(at: -0.25).point == path.sample(at: 0.75).point)
        #expect(path.sample(at: 1).point == path.sample(at: 0).point)
        #expect(abs(path.easedFraction(1.25) - path.easedFraction(0.25)) < 1e-9)
        #expect(abs(path.easedFraction(-0.75) - path.easedFraction(0.25)) < 1e-9)
    }

    @Test func offsetPointMovesInward() {
        #expect(border.offsetPoint(at: 50.0 / 300, inward: 4) == CGPoint(x: 50, y: 4))
        #expect(EdgePath(size: Self.size, inset: 0, route: .right).offsetPoint(at: 0.25, inward: 4)
            == CGPoint(x: 96, y: 25))
    }

    @Test(arguments: TraceRoute.allCases)
    func zeroSizeIsFinite(route: TraceRoute) {
        let empty = EdgePath(size: .zero, inset: 1.5, route: route)
        #expect(empty.loopLength == 0)
        let s = empty.sample(at: 0.3)
        #expect(s.point.x.isFinite && s.point.y.isFinite)
        #expect(empty.easedFraction(0.3).isFinite)
        _ = empty.segment(from: 0, to: 0.5)
        #expect(EdgePath(size: CGSize(width: 2, height: 2), inset: 1.5, route: route).loopLength == 0)
    }
}
#endif
