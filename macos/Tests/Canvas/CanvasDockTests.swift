#if os(macOS)
import Testing
@testable import Lostty

struct CanvasDockTests {
    @Test func theDockKeepsTheSavedOrderAndAddsNewAppsAtTheEnd() {
        #expect(CanvasDockApp.order(from: "", removed: "") == [.settings, .usage])
        #expect(CanvasDockApp.order(from: "usage,settings", removed: "") == [.usage, .settings])
        #expect(CanvasDockApp.order(from: "usage", removed: "") == [.usage, .settings])
    }

    @Test func unknownAndRepeatedNamesAreDropped() {
        #expect(CanvasDockApp.order(from: "usage,mail,usage,settings", removed: "") == [.usage, .settings])
    }

    @Test func removedAppsAreLeftOff() {
        #expect(CanvasDockApp.order(from: "usage,settings", removed: "usage") == [.settings])
    }

    @Test func anAppMovesToItsSlotAndTheOthersCloseUp() {
        let order: [CanvasDockApp] = [.settings, .usage]
        #expect(CanvasDockApp.moving(.settings, to: 1, in: order) == [.usage, .settings])
        #expect(CanvasDockApp.moving(.usage, to: 0, in: order) == [.usage, .settings])
        #expect(CanvasDockApp.moving(.usage, to: 5, in: order) == [.settings, .usage])
        #expect(CanvasDockApp.moving(.settings, to: -1, in: order) == [.settings, .usage])
    }

    @MainActor @Test func iconsGrowMostUnderThePointerAndLessFurtherOut() {
        #expect(CanvasDock.growth(distance: 0) == CanvasDock.magnified)
        let near = CanvasDock.growth(distance: CanvasDock.pitch)
        let far = CanvasDock.growth(distance: 2 * CanvasDock.pitch)
        #expect(near < CanvasDock.magnified && far < near && far > 1)
        #expect(CanvasDock.growth(distance: CanvasDock.reach) == 1)
        #expect(CanvasDock.growth(distance: 500) == 1)
    }

    @Test func eachAddMenuItemHasItsOwnKeyAndNoneIsTheDocksOrTheTicketsPanels() {
        let keys = CanvasAddMenuView.Item.allCases.map(\.key)
        #expect(keys == ["t", "a", "z"])
        #expect(Set(keys).count == keys.count)
        #expect(!keys.contains("d"))
        #expect(!keys.contains("m"))
    }
}
#endif
