import SwiftUI
import Testing
@testable import Lostty

struct CountdownRingTests {
    let rect = CGRect(x: 0, y: 0, width: 280, height: 280)

    @Test func startsAndEndsAtTopCentre() {
        let path = CountdownRing(cornerRadius: 24).path(in: rect)
        var first: CGPoint?
        path.forEach { element in
            if first == nil, case .move(let point) = element { first = point }
        }
        #expect(first == CGPoint(x: 140, y: 0))
        #expect(path.currentPoint == CGPoint(x: 140, y: 0))
    }

    @Test func runsClockwiseTowardTheTopRightFirst() {
        let path = CountdownRing(cornerRadius: 24).path(in: rect)
        var second: CGPoint?
        path.forEach { element in
            guard second == nil else { return }
            switch element {
            case .line(let point), .quadCurve(let point, _), .curve(let point, _, _): second = point
            default: break
            }
        }
        #expect((second?.x ?? 0) > 140)
        #expect(second?.y == 0)
    }

    @Test func staysInsideItsRect() {
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(CountdownRing(cornerRadius: 24).path(in: rect).boundingRect))
    }

    @Test func theArcRunsFromTwelveClockwiseAndRecedesTowardIt() {
        // As in the approved mock: the gap opens just left of 12 o'clock.
        #expect(CountdownRing.visible(1) == 0...1)
        #expect(CountdownRing.visible(0.75) == 0...0.75)
        #expect(CountdownRing.visible(0) == 0...0)
        #expect(CountdownRing.visible(1.5) == 0...1)
        #expect(CountdownRing.visible(-0.2) == 0...0)
    }
}
