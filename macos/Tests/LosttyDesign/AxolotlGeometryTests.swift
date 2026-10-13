import SwiftUI
import Testing
@testable import Ghostty

struct AxolotlGeometryTests {
    @Test func rightGillsMirrorTheLeft() {
        let left = AxolotlGeometry.gills(.left)
        let right = AxolotlGeometry.gills(.right)
        #expect(left.count == 3)
        for (l, r) in zip(left, right) {
            #expect(r.x == 100 - l.x)
            #expect(r.y == l.y)
            #expect(r.rotation == -l.rotation)
        }
    }

    @Test func gillsFanUpwardFromTopToBottom() {
        #expect(AxolotlGeometry.gills(.left).map(\.rotation) == [-42, -12, 18])
    }

    @Test func drawingStaysInsideItsBox() {
        let kinds: [AxolotlPart.Kind] = [.tail, .body, .belly, .limbs, .limbsWaving, .gills(.left), .gills(.right),
                                         .head, .highlight, .blush]
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        for kind in kinds {
            #expect(box.contains(AxolotlPart.unitPath(kind).boundingRect))
        }
        for part: AxolotlRaisedArm.Part in [.arm, .hand, .marks] {
            #expect(box.contains(AxolotlRaisedArm.unitPath(part).boundingRect))
        }
        #expect(box.contains(AxolotlCheck().path(in: box).boundingRect))
    }

    @Test func theWavingArmIsRaisedOnItsOwnRight() {
        // Its right is the viewer's left; the hand goes up past the cheek.
        let hand = AxolotlGeometry.hand
        let shoulder = AxolotlGeometry.shoulder
        #expect(hand.x < shoulder.x && hand.y < shoulder.y - 15)
        // That arm's stub isn't drawn as well.
        let stub = CGPoint(x: 39, y: 80)
        #expect(AxolotlPart.unitPath(.limbs).contains(stub))
        #expect(!AxolotlPart.unitPath(.limbsWaving).contains(stub))
    }
}
