#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct ExtensionSidebarModelTests {
    @Test func startsWithNothingOpen() {
        let model = ExtensionSidebarModel()
        #expect(model.active == nil)
        #expect(model.focusedSurfaceID == nil)
    }

    @Test func clickingAnIconOpensItAndClickingAgainCloses() {
        let model = ExtensionSidebarModel()
        model.select(.skins)
        #expect(model.active == .skins)
        model.select(.skins)
        #expect(model.active == nil)
    }

    @Test func clickingAnotherIconSwitchesToIt() {
        let model = ExtensionSidebarModel()
        model.select(.branches)
        model.select(.skins)
        #expect(model.active == .skins)
    }

    @Test func closeLeavesAnyOpenApp() {
        let model = ExtensionSidebarModel()
        model.select(.branches)
        model.close()
        #expect(model.active == nil)
    }

    @Test func sidebarOrderIsBranchesThenSkins() {
        #expect(LosttyExtension.allCases == [.branches, .skins])
        #expect(LosttyExtension.branches.title == "Branches")
        #expect(LosttyExtension.skins.title == "Skins")
    }

    @Test func branchesOpensInTheSidebarAndSkinsOverTheTerminal() {
        #expect(LosttyExtension.branches.presentation == .sidebar(width: 340))
        #expect(LosttyExtension.skins.presentation == .overlay)
    }

    @Test func tracksTheFocusedPane() {
        let model = ExtensionSidebarModel()
        let pane = UUID()
        model.focusedSurfaceID = pane
        #expect(model.focusedSurfaceID == pane)
    }
}
#endif
