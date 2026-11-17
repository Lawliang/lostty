#if os(macOS)
import CoreGraphics
import Foundation
import Testing
@testable import Lostty

struct CanvasArrowsTests {
    let shown = CGRect(x: 1000, y: 1000, width: 800, height: 600)
    let size = CGSize(width: 800, height: 600)

    func target(_ x: CGFloat, _ y: CGFloat) -> CanvasArrows.Target {
        CanvasArrows.Target(pane: UUID(), frame: CGRect(x: x - 100, y: y - 50, width: 200, height: 100), name: "Ada")
    }

    @Test func aCardOnScreenGetsNoArrow() {
        #expect(CanvasArrows.markers([target(1400, 1300)], shown: shown, zoom: 1, size: size).isEmpty)
    }

    @Test func aCardOffToTheRightGetsAnArrowOnTheRightEdgePointingRight() throws {
        let marker = try #require(CanvasArrows.markers([target(3000, 1300)], shown: shown, zoom: 1, size: size).first)
        #expect(marker.center == CGPoint(x: 800 - CanvasArrows.inset, y: 300))
        #expect(abs(marker.angle) < 0.001)
        #expect(marker.name == "Ada")
    }

    @Test func aCardAboveAndLeftSitsOnTheEdgeItsDirectionCrosses() throws {
        let marker = try #require(CanvasArrows.markers([target(1400, 0)], shown: shown, zoom: 1, size: size).first)
        #expect(marker.center.y == CanvasArrows.inset)
        #expect(abs(marker.angle + .pi / 2) < 0.001)
        let corner = try #require(CanvasArrows.markers([target(-2000, -2000)], shown: shown, zoom: 1, size: size).first)
        #expect(corner.center.x >= CanvasArrows.inset - 0.001 && corner.center.y >= CanvasArrows.inset - 0.001)
        #expect(corner.angle < -.pi / 2)
    }

    @Test func zoomScalesWhereTheCardIsFromTheMiddle() throws {
        // At 50% the view shows twice as much: a card just off the right at
        // 100% is on screen.
        let wide = CGRect(x: 1000, y: 1000, width: 1600, height: 1200)
        #expect(CanvasArrows.markers([target(2000, 1300)], shown: wide, zoom: 0.5, size: size).isEmpty)
    }

    @Test func markersThatWouldOverlapMergeOldestFirst() throws {
        let first = target(3000, 1300), second = target(3200, 1310), other = target(1400, 4000)
        let markers = CanvasArrows.markers([first, second, other], shown: shown, zoom: 1, size: size)
        #expect(markers.count == 2)
        #expect(markers[0].panes == [first.pane, second.pane])
        #expect(markers[1].panes == [other.pane])
    }
}
#endif
