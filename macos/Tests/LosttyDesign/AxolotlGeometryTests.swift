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
        let kinds: [AxolotlPart.Kind] = [.tail, .body, .belly, .limbs, .gills(.left), .gills(.right),
                                         .head, .highlight, .blush]
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        for kind in kinds {
            #expect(box.contains(AxolotlPart.unitPath(kind).boundingRect))
        }
        #expect(box.contains(AxolotlCheck().path(in: box).boundingRect))
    }
}
