#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct CanvasDropTests {
    @Test func aWindowHeldOverlappingTheCanvasForThreeSecondsMergesIn() {
        let since = Date(timeIntervalSinceReferenceDate: 100)
        #expect(!CanvasDrop.held(since: nil, now: since.addingTimeInterval(5)))
        #expect(!CanvasDrop.held(since: since, now: since.addingTimeInterval(2.9)))
        #expect(CanvasDrop.held(since: since, now: since.addingTimeInterval(3)))
    }

    @Test func anyOverlapWithTheCanvasCounts() {
        let canvas = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(CanvasDrop.overlap(CGRect(x: 890, y: 650, width: 400, height: 300), canvas)
            == CGRect(x: 890, y: 650, width: 10, height: 50))
        // Touching its edge isn't overlapping it.
        #expect(CanvasDrop.overlap(CGRect(x: 900, y: 100, width: 400, height: 300), canvas) == nil)
        #expect(CanvasDrop.overlap(CGRect(x: 0, y: 900, width: 400, height: 300), canvas) == nil)
    }

    @Test func theWarpPlaysRoundTheWindowAndThePointYDown() {
        let screen = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let geometry = CanvasAbsorb.Geometry(
            window: CGRect(x: 500, y: 300, width: 600, height: 400), target: CGPoint(x: 800, y: 690), screen: screen)
        // The window, the rings' room above it, and a margin.
        #expect(geometry.frame.contains(CGRect(x: 500, y: 300, width: 600, height: 400)))
        #expect(geometry.frame.maxY >= 690 + CanvasAbsorb.Geometry.rippleRadius / 2)
        // In the overlay, y down: the point sits near the window's top.
        #expect(geometry.window.minY == geometry.frame.maxY - 700)
        #expect(geometry.target == CGPoint(x: 800 - geometry.frame.minX, y: geometry.frame.maxY - 690))
        // The farthest corner is a bottom one.
        #expect(abs(geometry.reach - hypot(300, 390)) < 1e-9)
    }

    @Test func theWarpStaysOnItsScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let geometry = CanvasAbsorb.Geometry(
            window: CGRect(x: 10, y: 10, width: 400, height: 760), target: CGPoint(x: 200, y: 780), screen: screen)
        #expect(screen.contains(geometry.frame))
    }
}
#endif
