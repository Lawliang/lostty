import Testing
@testable import LosttyRemote

struct RowPullTests {
    @Test func aLeftwardDragIsAPullAndAVerticalOneIsAScroll() {
        #expect(RowPull.isSideways(dx: -20, dy: 4))
        #expect(!RowPull.isSideways(dx: -20, dy: 18))  // more scroll than pull
        #expect(!RowPull.isSideways(dx: 20, dy: 0))  // rightward: nothing to reveal
        #expect(!RowPull.isSideways(dx: 0, dy: -30))
    }

    @Test func lettingGoRefreshesOnlyPastTheThreshold() {
        #expect(!RowPull.refreshes(dx: -(RowPull.threshold - 1)))
        #expect(RowPull.refreshes(dx: -RowPull.threshold))
        #expect(!RowPull.refreshes(dx: 40))
    }

    @Test func progressFillsTowardTheThreshold() {
        #expect(RowPull.progress(dx: 0) == 0)
        #expect(RowPull.progress(dx: -RowPull.threshold / 2) == 0.5)
        #expect(RowPull.progress(dx: -RowPull.threshold * 3) == 1)
        #expect(RowPull.progress(dx: 30) == 0)
    }

    @Test func theRowFollowsLeftButNeverPastItsLimit() {
        #expect(RowPull.offset(dx: 0) == 0)
        #expect(RowPull.offset(dx: 25) == 0)
        let near = RowPull.offset(dx: -10)
        #expect(near < 0 && near > -10)  // follows, a little behind the finger
        let far = RowPull.offset(dx: -1_000)
        #expect(far < -RowPull.limit * 0.99 && far >= -RowPull.limit)
        // Further always moves it further.
        #expect(RowPull.offset(dx: -80) < RowPull.offset(dx: -60))
    }
}
