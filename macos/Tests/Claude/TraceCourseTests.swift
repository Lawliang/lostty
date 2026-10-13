#if os(macOS)
import SwiftUI
import Testing
@testable import Lostty

struct TraceCourseTests {
    // 100x50 pane at the origin.
    let rect = CGRect(x: 0, y: 0, width: 100, height: 50)

    @Test func cornersAndNeighbors() {
        #expect(Corner.bottomRight.point(in: rect) == CGPoint(x: 100, y: 50))
        #expect(Set(Corner.topLeft.neighbors) == [.topRight, .bottomLeft])
        #expect(Set(Corner.bottomRight.neighbors) == [.topRight, .bottomLeft])
        #expect(Corner.inwardNormal(.bottomLeft, .bottomRight) == CGVector(dx: 0, dy: -1))
        #expect(Corner.inwardNormal(.bottomRight, .topRight) == CGVector(dx: -1, dy: 0))
    }

    @Test func onTheCourseTheHeadKeepsGoing() {
        let all = TraceCourse.route(.all)
        #expect(all.next(after: .topLeft) == .topRight)
        #expect(all.next(after: .bottomLeft) == .topLeft)
        #expect(TraceCourse.route(.right).next(after: .topRight) == .bottomRight)
        #expect(TraceCourse.route(.right).next(after: .bottomRight) == .topRight)
        #expect(TraceCourse.route(.top).next(after: .topLeft) == .topRight)
        #expect(TraceCourse.route(.left).next(after: .bottomLeft) == .topLeft)
        #expect(TraceCourse.subagents.next(after: .bottomRight) == .bottomLeft)
        #expect(TraceCourse.subagents.next(after: .bottomLeft) == .bottomRight)
    }

    // Off the course, the head takes the side that leads onto it.
    @Test func offTheCourseTheHeadMakesForIt() {
        #expect(TraceCourse.subagents.next(after: .topRight) == .bottomRight)
        #expect(TraceCourse.subagents.next(after: .topLeft) == .bottomLeft)
        #expect(TraceCourse.route(.right).next(after: .bottomLeft) == .bottomRight)
        #expect(TraceCourse.route(.top).next(after: .bottomRight) == .topRight)
        #expect(TraceCourse.route(.left).next(after: .bottomRight) == .bottomLeft)
    }

    @Test func lapLengths() {
        #expect(TraceCourse.route(.all).lapLength(in: rect) == 300)
        #expect(TraceCourse.route(.right).lapLength(in: rect) == 100)
        #expect(TraceCourse.route(.left).lapLength(in: rect) == 100)
        #expect(TraceCourse.route(.top).lapLength(in: rect) == 200)
        #expect(TraceCourse.subagents.lapLength(in: rect) == 200)
    }

    @Test func outlines() {
        #expect(TraceCourse.route(.all).outline(in: rect).boundingRect == rect)
        #expect(TraceCourse.route(.right).outline(in: rect).boundingRect == CGRect(x: 100, y: 0, width: 0, height: 50))
        #expect(TraceCourse.subagents.outline(in: rect).boundingRect == CGRect(x: 0, y: 50, width: 100, height: 0))
    }

    // MARK: Motion (one second per leg)

    func corners(_ motion: TraceMotion) -> [Corner] {
        guard let first = motion.legs.first else { return [] }
        return [first.from] + motion.legs.map(\.to)
    }

    @Test func aFreshTraceStartsAtTheCoursesFirstCorner() {
        var motion = TraceMotion()
        motion.advance(to: 0, course: .route(.right), legSeconds: 1)
        #expect(motion.legs == [.init(from: .topRight, to: .bottomRight, start: 0)])
        motion.advance(to: 2.5, course: .route(.right), legSeconds: 1)
        #expect(corners(motion) == [.topRight, .bottomRight, .topRight, .bottomRight])
        #expect(motion.legs.map(\.start) == [0, 1, 2])
    }

    // Subagents take over mid-leg: the head finishes the side it is on,
    // goes down to the bottom, then keeps to the bottom edge.
    @Test func handOffToTheBottomEdgeWaitsForTheCorner() {
        var motion = TraceMotion()
        motion.advance(to: 1.5, course: .route(.right), legSeconds: 1)  // going up
        motion.advance(to: 1.9, course: .subagents, legSeconds: 1)
        #expect(corners(motion) == [.topRight, .bottomRight, .topRight])
        motion.advance(to: 4.5, course: .subagents, legSeconds: 1)
        #expect(corners(motion) == [.topRight, .bottomRight, .topRight, .bottomRight, .bottomLeft, .bottomRight])
    }

    @Test func allAroundReachesTheBottomClockwise() {
        var motion = TraceMotion()
        motion.advance(to: 0.5, course: .route(.all), legSeconds: 1)
        motion.advance(to: 3.5, course: .subagents, legSeconds: 1)
        #expect(corners(motion) == [.topLeft, .topRight, .bottomRight, .bottomLeft, .bottomRight])
    }

    @Test func topOnlyComesDownTheRightSide() {
        var motion = TraceMotion()
        motion.advance(to: 0.5, course: .route(.top), legSeconds: 1)
        motion.advance(to: 2.5, course: .subagents, legSeconds: 1)
        #expect(corners(motion) == [.topLeft, .topRight, .bottomRight, .bottomLeft])
    }

    @Test func claudeTakingOverReturnsToTheRoute() {
        var motion = TraceMotion()
        motion.advance(to: 0.5, course: .subagents, legSeconds: 1)  // bottomRight → bottomLeft
        motion.advance(to: 3.5, course: .route(.right), legSeconds: 1)
        #expect(corners(motion) == [.bottomRight, .bottomLeft, .bottomRight, .topRight, .bottomRight])
    }

    // The bottom glow lights when the head, sent by subagents, reaches the
    // bottom edge (not while it is on its way down), and fades once it
    // leaves for the route.
    @Test func bottomGlowLightsWhenTheHeadReachesTheBottom() {
        var motion = TraceMotion()
        let fade = TraceMotion.glowFade
        motion.advance(to: 1.5, course: .route(.right), legSeconds: 1)  // going up
        #expect(motion.bottomGlow(at: 1.5) == 0)
        motion.advance(to: 2.5, course: .subagents, legSeconds: 1)      // back down the right side
        #expect(motion.bottomGlow(at: 2.5) == 0)
        motion.advance(to: 3 + fade / 2, course: .subagents, legSeconds: 1)  // on the bottom since 3
        #expect(abs(motion.bottomGlow(at: 3 + fade / 2) - 0.5) < 1e-9)
        motion.advance(to: 4.5, course: .subagents, legSeconds: 1)
        #expect(motion.bottomGlow(at: 4.5) == 1)

        // Claude takes over: the head finishes the bottom leg, then leaves.
        motion.advance(to: 4.9, course: .route(.right), legSeconds: 1)
        #expect(motion.bottomGlow(at: 4.9) == 1)
        motion.advance(to: 5 + fade / 2, course: .route(.right), legSeconds: 1)
        #expect(abs(motion.bottomGlow(at: 5 + fade / 2) - 0.5) < 1e-9)
        motion.advance(to: 6, course: .route(.right), legSeconds: 1)
        #expect(motion.bottomGlow(at: 6) == 0)
    }

    @Test func allAroundCrossingTheBottomWhileClaudeWorksHasNoGlow() {
        var motion = TraceMotion()
        motion.advance(to: 2.5, course: .route(.all), legSeconds: 1)  // bottomRight → bottomLeft
        #expect(motion.legs.last?.from == .bottomRight)
        #expect(motion.bottomGlow(at: 2.5) == 0)
    }

    @Test func aTraceStartingWithSubagentsGlowsFromTheStart() {
        var motion = TraceMotion()
        motion.advance(to: 0.2, course: .subagents, legSeconds: 1)
        #expect(motion.bottomGlow(at: 0.2) > 0)
    }

    @Test func historyIsTrimmed() {
        var motion = TraceMotion()
        motion.advance(to: 1000, course: .route(.all), legSeconds: 0.6)
        #expect(motion.legs.count == TraceMotion.keptLegs)
    }

    // MARK: The travelled path

    func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    @Test func headEasesAlongTheLeg() {
        var motion = TraceMotion()
        motion.advance(to: 0.5, course: .route(.right), legSeconds: 1)
        let mid = motion.path(in: rect, at: 0.5, legSeconds: 1)
        #expect(abs(mid.length - 25) < 1e-9)
        let head = mid.sample(at: 1)
        #expect(close(head.point, CGPoint(x: 100, y: 25)))
        #expect(head.tangent == CGVector(dx: 0, dy: 1))
        #expect(head.normal == CGVector(dx: -1, dy: 0))
        // A sine speed: a quarter of the way in time is ~15% of the way.
        let early = motion.path(in: rect, at: 0.25, legSeconds: 1).sample(at: 1).point
        #expect(abs(early.y - 50 * (1 - cos(.pi / 4)) / 2) < 1e-6)
    }

    @Test func pathFollowsTheHeadAroundTheTurnaround() {
        var motion = TraceMotion()
        motion.advance(to: 1.5, course: .route(.right), legSeconds: 1)
        let path = motion.path(in: rect, at: 1.5, legSeconds: 1)
        #expect(abs(path.length - 75) < 1e-9)
        #expect(close(path.sample(at: 1).point, CGPoint(x: 100, y: 25)))
        #expect(path.sample(at: 1).tangent == CGVector(dx: 0, dy: -1))
        #expect(path.sample(at: 50.0 / 75).point == CGPoint(x: 100, y: 50))
    }

    @Test func zeroSizePaneStaysFinite() {
        var motion = TraceMotion()
        motion.advance(to: 3.3, course: .route(.all), legSeconds: 1)
        let path = motion.path(in: TraceOverlay.edgeRect(.zero), at: 3.3, legSeconds: 1)
        #expect(path.length == 0)
        let s = path.sample(at: 0.5)
        #expect(s.point.x.isFinite && s.point.y.isFinite)
        #expect(path.segment(from: 0, to: 1).isEmpty)
    }
}
#endif
