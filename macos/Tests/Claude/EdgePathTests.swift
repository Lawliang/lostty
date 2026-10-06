#if os(macOS)
import SwiftUI
import Testing
@testable import Ghostty

struct EdgePathTests {
    // 100x50 pane, inset 0 → perimeter 300. Top edge = 0..<1/3.
    let path = EdgePath(size: CGSize(width: 100, height: 50), inset: 0)

    @Test func perimeter() {
        #expect(path.perimeter == 300)
        #expect(EdgePath(size: CGSize(width: 100, height: 50), inset: 5).perimeter == 260)
    }

    @Test func walksClockwiseFromTopLeft() {
        #expect(path.sample(at: 0).point == CGPoint(x: 0, y: 0))
        #expect(path.sample(at: 50.0 / 300).point == CGPoint(x: 50, y: 0))
        #expect(path.sample(at: 125.0 / 300).point == CGPoint(x: 100, y: 25))
        #expect(path.sample(at: 200.0 / 300).point == CGPoint(x: 50, y: 50))
        #expect(path.sample(at: 275.0 / 300).point == CGPoint(x: 0, y: 25))
    }

    @Test func tangentsAndInwardNormals() {
        let top = path.sample(at: 0.1)
        #expect(top.tangent == CGVector(dx: 1, dy: 0))
        #expect(top.normal == CGVector(dx: 0, dy: 1))
        let right = path.sample(at: 125.0 / 300)
        #expect(right.tangent == CGVector(dx: 0, dy: 1))
        #expect(right.normal == CGVector(dx: -1, dy: 0))
        let bottom = path.sample(at: 200.0 / 300)
        #expect(bottom.normal == CGVector(dx: 0, dy: -1))
        let left = path.sample(at: 275.0 / 300)
        #expect(left.normal == CGVector(dx: 1, dy: 0))
    }

    @Test func fractionsWrap() {
        #expect(path.sample(at: 1.25).point == path.sample(at: 0.25).point)
        #expect(path.sample(at: -0.25).point == path.sample(at: 0.75).point)
        #expect(path.sample(at: 1).point == path.sample(at: 0).point)
    }

    @Test func offsetPointMovesInward() {
        #expect(path.offsetPoint(at: 50.0 / 300, inward: 4) == CGPoint(x: 50, y: 4))
    }

    @Test func segmentAcrossTheStartCorner() {
        let seg = path.segment(from: -0.05, to: 0.05)
        #expect(!seg.isEmpty)
        let box = seg.boundingRect
        #expect(box.minX <= 0.001 && box.maxX >= 14.9)
        #expect(box.maxY >= 14.9)
    }

    // Easing: each edge takes time in proportion to its length, the head
    // eases out of one corner and into the next.
    @Test func easingKeepsCornersAndEdgeMidpoints() {
        for f in [0.0, 100.0 / 300, 150.0 / 300, 250.0 / 300] {
            #expect(abs(path.easedFraction(f) - f) < 1e-9)
        }
        #expect(abs(path.easedFraction(50.0 / 300) - 50.0 / 300) < 1e-9)
        #expect(abs(path.easedFraction(125.0 / 300) - 125.0 / 300) < 1e-9)
    }

    @Test func easingIsSlowNearCornersAndFastMidEdge() {
        let lin = 5.0 / 300
        // Just after the top-left corner the head lags behind linear motion...
        #expect(path.easedFraction(lin) < lin)
        // ...and just before the top-right corner it is ahead (decelerating).
        #expect(path.easedFraction(95.0 / 300) > 95.0 / 300)
        // Mid-edge it covers more ground per step than near the corner.
        let nearCorner = path.easedFraction(2.0 / 300) - path.easedFraction(0)
        let midEdge = path.easedFraction(52.0 / 300) - path.easedFraction(50.0 / 300)
        #expect(midEdge > nearCorner * 2)
        // Never fully stops at a corner.
        #expect(nearCorner > 0)
    }

    @Test func easingWrapsAndStaysFinite() {
        #expect(abs(path.easedFraction(1.25) - path.easedFraction(0.25)) < 1e-9)
        let empty = EdgePath(size: .zero, inset: 1.5)
        #expect(empty.easedFraction(0.3).isFinite)
    }

    @Test func zeroSizeIsFinite() {
        let empty = EdgePath(size: .zero, inset: 1.5)
        #expect(empty.perimeter == 0)
        let s = empty.sample(at: 0.3)
        #expect(s.point.x.isFinite && s.point.y.isFinite)
        _ = empty.segment(from: 0, to: 0.5)
        let tiny = EdgePath(size: CGSize(width: 2, height: 2), inset: 1.5)
        #expect(tiny.perimeter == 0)
    }
}
#endif
