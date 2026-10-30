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
}
#endif
