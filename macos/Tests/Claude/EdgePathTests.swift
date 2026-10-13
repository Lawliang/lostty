#if os(macOS)
import SwiftUI
import Testing
@testable import Lostty

struct EdgePathTests {
    // Along the top (100pt) then down the right side (50pt): length 150.
    let path = EdgePath(runs: [
        .init(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0),
              tangent: CGVector(dx: 1, dy: 0), normal: CGVector(dx: 0, dy: 1)),
        .init(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 100, y: 50),
              tangent: CGVector(dx: 0, dy: 1), normal: CGVector(dx: -1, dy: 0)),
    ])

    @Test func lengthIsTheRunsTogether() {
        #expect(path.length == 150)
    }

    @Test func samplesFromTheOldestPointToTheHead() {
        #expect(path.sample(at: 0).point == CGPoint(x: 0, y: 0))
        #expect(path.sample(at: 50.0 / 150).point == CGPoint(x: 50, y: 0))
        #expect(path.sample(at: 125.0 / 150).point == CGPoint(x: 100, y: 25))
        #expect(path.sample(at: 1).point == CGPoint(x: 100, y: 50))
    }

    @Test func tangentsAndInwardNormalsComeFromTheRun() {
        let top = path.sample(at: 0.2)
        #expect(top.tangent == CGVector(dx: 1, dy: 0))
        #expect(top.normal == CGVector(dx: 0, dy: 1))
        let right = path.sample(at: 0.9)
        #expect(right.tangent == CGVector(dx: 0, dy: 1))
        #expect(right.normal == CGVector(dx: -1, dy: 0))
    }

    @Test func fractionsClamp() {
        #expect(path.sample(at: -0.5).point == path.sample(at: 0).point)
        #expect(path.sample(at: 1.5).point == path.sample(at: 1).point)
    }

    @Test func offsetPointMovesInward() {
        #expect(path.offsetPoint(at: 50.0 / 150, inward: 4) == CGPoint(x: 50, y: 4))
        #expect(path.offsetPoint(at: 125.0 / 150, inward: 4) == CGPoint(x: 96, y: 25))
    }

    @Test func segmentAcrossTheCorner() {
        let box = path.segment(from: 0.5, to: 0.9).boundingRect
        #expect(abs(box.minX - 75) < 0.001 && box.maxX == 100)
        #expect(box.minY == 0 && abs(box.maxY - 35) < 0.001)
        #expect(path.segment(from: 0.4, to: 0.4).isEmpty)
    }

    // The head just reached a corner: the new leg is still zero long, but
    // the head keeps the direction it came from.
    @Test func zeroLengthHeadRunKeepsTheLastDirection() {
        let resting = EdgePath(runs: path.runs + [
            .init(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 100, y: 50),
                  tangent: CGVector(dx: -1, dy: 0), normal: CGVector(dx: 0, dy: -1)),
        ])
        #expect(resting.length == 150)
        let head = resting.sample(at: 1)
        #expect(head.point == CGPoint(x: 100, y: 50))
        #expect(head.tangent == CGVector(dx: 0, dy: 1))
    }

    @Test func emptyPathIsFinite() {
        let empty = EdgePath(runs: [])
        #expect(empty.length == 0)
        #expect(empty.sample(at: 0.5).point == .zero)
        #expect(empty.segment(from: 0, to: 1).isEmpty)
    }
}
#endif
