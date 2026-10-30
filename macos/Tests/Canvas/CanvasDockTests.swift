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

    @Test func eachAddMenuItemHasItsOwnKeyAndNoneIsTheDocks() {
        let keys = CanvasAddMenuView.Item.allCases.map(\.key)
        #expect(keys == ["t", "m", "z"])
        #expect(Set(keys).count == keys.count)
        #expect(!keys.contains("d"))
    }
}
#endif
