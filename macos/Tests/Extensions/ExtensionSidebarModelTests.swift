#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct ExtensionSidebarModelTests {
    /// A sidebar whose Branches model reads a scripted world.
    private func makeModel() throws -> (ExtensionSidebarModel, BranchesModel) {
        let branches = BranchesModel(env: try FakeBranchesWorld().environment())
        return (ExtensionSidebarModel(branches: branches), branches)
    }

    @Test func startsWithNothingOpen() throws {
        let (model, _) = try makeModel()
        #expect(model.active == nil)
        #expect(model.focusedSurfaceID == nil)
    }

    @Test func clickingAnIconOpensItAndClickingAgainCloses() throws {
        let (model, _) = try makeModel()
        model.select(.skins)
        #expect(model.active == .skins)
        model.select(.skins)
        #expect(model.active == nil)
    }

    @Test func clickingAnotherIconSwitchesToIt() throws {
        let (model, _) = try makeModel()
        model.select(.branches)
        model.select(.skins)
        #expect(model.active == .skins)
    }

    @Test func closeLeavesAnyOpenApp() throws {
        let (model, _) = try makeModel()
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

    @Test func tracksTheFocusedPane() throws {
        let (model, _) = try makeModel()
        let pane = UUID()
        model.focusedSurfaceID = pane
        #expect(model.focusedSurfaceID == pane)
    }

    @Test func openingBranchesOpensItsModelAndLeavingClosesIt() throws {
        let (model, branches) = try makeModel()
        model.select(.branches)
        #expect(branches.isOpen)
        model.select(.skins)
        #expect(branches.isOpen == false)
    }
}
#endif
