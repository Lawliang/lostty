#if os(macOS)
import Foundation
import Testing
@testable import Lostty

@MainActor
struct ExtensionSidebarModelTests {
    /// A sidebar whose Branches model reads a scripted world.
    private func makeModel(channel: LosttyChannel = .beta) throws -> (ExtensionSidebarModel, BranchesModel) {
        let branches = BranchesModel(env: try FakeBranchesWorld().environment())
        return (ExtensionSidebarModel(branches: branches, channel: channel), branches)
    }

    @Test func branchesIsInTheBetaOnly() {
        #expect(LosttyExtension.available(in: .beta) == [.branches, .skins])
        #expect(LosttyExtension.available(in: .stable) == [.skins])
    }

    @Test func stableNeverOpensBranches() throws {
        let (model, branches) = try makeModel(channel: .stable)
        #expect(model.available == [.skins])
        model.select(.branches)
        #expect(model.active == nil)
        #expect(branches.isOpen == false)
        model.select(.skins)
        #expect(model.active == .skins)
    }

    @Test func theMascotIsInTheBetaOnly() throws {
        #expect(try makeModel(channel: .beta).0.showsMascot)
        #expect(try makeModel(channel: .stable).0.showsMascot == false)
    }

    @Test func startsWithNothingOpen() throws {
        let (model, _) = try makeModel()
        #expect(model.active == nil)
        #expect(model.focusedSurfaceID == nil)
    }

    @Test func theBarShowsUsageUntilTheAppsButton() throws {
        let (model, _) = try makeModel()
        #expect(model.showsApps == false)
        model.toggleApps()
        #expect(model.showsApps)
        model.toggleApps()
        #expect(model.showsApps == false)
    }

    @Test func hidingTheAppsLeavesAnOpenAppOpen() throws {
        let (model, _) = try makeModel()
        model.toggleApps()
        model.select(.skins)
        model.toggleApps()
        #expect(model.active == .skins)
        #expect(model.showsApps == false)
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

    @Test func rowOrderIsBranchesThenSkins() {
        #expect(LosttyExtension.allCases == [.branches, .skins])
        #expect(LosttyExtension.branches.title == "Branches")
        #expect(LosttyExtension.skins.title == "Skins")
    }

    @Test func branchesCoversTheWindowAndSkinsTheTerminal() {
        #expect(LosttyExtension.branches.presentation == .window)
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

    @Test func closingAnAppHandsFocusBackToThePane() throws {
        let (model, _) = try makeModel()
        var focused = 0
        model.focusTerminal = { focused += 1 }
        model.select(.branches)
        #expect(focused == 0)
        model.close()
        #expect(focused == 1)
        model.select(.skins)
        model.select(.skins)
        #expect(focused == 2)
        model.select(.branches)
        model.select(.branches)
        #expect(focused == 3)
    }

    @Test func leavingBranchesForAnotherAppHandsFocusBack() throws {
        let (model, _) = try makeModel()
        var focused = 0
        model.focusTerminal = { focused += 1 }
        model.select(.skins)
        model.select(.branches)
        #expect(focused == 0)
        model.select(.skins)
        #expect(focused == 1)
    }

    @Test func closingWithNothingOpenLeavesFocusAlone() throws {
        let (model, _) = try makeModel()
        var focused = 0
        model.focusTerminal = { focused += 1 }
        model.close()
        #expect(focused == 0)
    }
}
#endif
