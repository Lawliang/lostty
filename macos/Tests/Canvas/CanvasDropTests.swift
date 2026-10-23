#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct CanvasDropTests {
    @Test func aWindowHeldOverTheCanvasForTwoSecondsMergesIn() {
        let since = Date(timeIntervalSinceReferenceDate: 100)
        #expect(!CanvasDrop.merges(heldSince: nil, now: since.addingTimeInterval(5)))
        #expect(!CanvasDrop.merges(heldSince: since, now: since.addingTimeInterval(1.9)))
        #expect(CanvasDrop.merges(heldSince: since, now: since.addingTimeInterval(2)))
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
