#if os(macOS)
import SwiftUI
import Testing
@testable import Ghostty

struct EdgePathTests {
    // 100x50 pane, inset 0 → round trip 100. Down the right edge = 0..<½,
    // back up = ½..<1.
    let path = EdgePath(size: CGSize(width: 100, height: 50), inset: 0)

    @Test func loopLength() {
        #expect(path.loopLength == 100)
        #expect(EdgePath(size: CGSize(width: 100, height: 50), inset: 5).loopLength == 80)
    }

    @Test func shuttlesOnTheRightEdge() {
        #expect(path.sample(at: 0).point == CGPoint(x: 100, y: 0))
        #expect(path.sample(at: 0.25).point == CGPoint(x: 100, y: 25))
        #expect(path.sample(at: 0.5).point == CGPoint(x: 100, y: 50))
        #expect(path.sample(at: 0.75).point == CGPoint(x: 100, y: 25))
        #expect(path.sample(at: 0.9).point == CGPoint(x: 100, y: 10))
    }

    @Test func neverLeavesTheRightEdge() {
        for i in 0..<200 {
            #expect(path.sample(at: Double(i) / 200).point.x == 100)
        }
    }

    @Test func tangentsFlipAndNormalsPointInward() {
        let down = path.sample(at: 0.2)
        #expect(down.tangent == CGVector(dx: 0, dy: 1))
        #expect(down.normal == CGVector(dx: -1, dy: 0))
        let up = path.sample(at: 0.7)
        #expect(up.tangent == CGVector(dx: 0, dy: -1))
        #expect(up.normal == CGVector(dx: -1, dy: 0))
    }

    @Test func fractionsWrap() {
        #expect(path.sample(at: 1.25).point == path.sample(at: 0.25).point)
        #expect(path.sample(at: -0.25).point == path.sample(at: 0.75).point)
        #expect(path.sample(at: 1).point == path.sample(at: 0).point)
    }

    @Test func offsetPointMovesInward() {
        #expect(path.offsetPoint(at: 0.25, inward: 4) == CGPoint(x: 96, y: 25))
    }

    @Test func segmentFoldsBackAtTheBottom() {
        let seg = path.segment(from: 0.4, to: 0.6)
        #expect(!seg.isEmpty)
        let box = seg.boundingRect
        #expect(box.minX == 100 && box.maxX == 100)
        #expect(abs(box.minY - 40) < 0.001 && abs(box.maxY - 50) < 0.001)
    }

    @Test func lineIsTheRightEdge() {
        let box = path.line.boundingRect
        #expect(box == CGRect(x: 100, y: 0, width: 0, height: 50))
    }

    // Easing: each leg takes half the lap. Lap positions 0 and ½ are the
    // turnarounds; within a leg the speed is a sine: zero at each end,
    // fastest mid-edge.
    @Test func eachLegTakesHalfTheLap() {
        #expect(abs(path.easedFraction(0) - 0) < 1e-9)
        #expect(abs(path.easedFraction(0.5) - 0.5) < 1e-9)
        // Halfway through a leg's time is halfway along the edge.
        #expect(abs(path.easedFraction(0.25) - 0.25) < 1e-9)
        #expect(abs(path.easedFraction(0.75) - 0.75) < 1e-9)
    }

    @Test func speedIsASineAlongEachLeg() {
        // Speed down the edge (lap 0..½), in points per lap-fraction.
        func speed(at u: Double) -> Double {
            let du = 0.0005
            let a = path.easedFraction(u / 2), b = path.easedFraction((u + du) / 2)
            return (b - a) * path.loopLength / (du / 2)
        }
        let peak = speed(at: 0.5)
        #expect(speed(at: 0) / peak < 0.01)           // at rest leaving the top
        #expect(speed(at: 0.9995) / peak < 0.01)      // at rest arriving at the bottom
        for u in stride(from: 0.1, through: 0.9, by: 0.1) {
            #expect(abs(speed(at: u) / peak - sin(.pi * u)) < 0.02)
        }
    }

    @Test func easingWrapsAndStaysFinite() {
        #expect(abs(path.easedFraction(1.25) - path.easedFraction(0.25)) < 1e-9)
        #expect(abs(path.easedFraction(-0.75) - path.easedFraction(0.25)) < 1e-9)
        let empty = EdgePath(size: .zero, inset: 1.5)
        #expect(empty.easedFraction(0.3).isFinite)
    }

    @Test func zeroSizeIsFinite() {
        let empty = EdgePath(size: .zero, inset: 1.5)
        #expect(empty.loopLength == 0)
        let s = empty.sample(at: 0.3)
        #expect(s.point.x.isFinite && s.point.y.isFinite)
        _ = empty.segment(from: 0, to: 0.5)
        let tiny = EdgePath(size: CGSize(width: 2, height: 2), inset: 1.5)
        #expect(tiny.loopLength == 0)
    }
}
#endif
