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

    @Test func aCanvasCardHasNoMascot() {
        #expect(ExtensionSidebarModel(channel: .beta, mascot: false).showsMascot == false)
    }

    @Test func theIconRowStartsTuckedAway() throws {
        #expect(try makeModel().0.iconRowShown == false)
    }

    @Test func draggingTheHandleRevealsTheRowUpToItsHeight() {
        let h = ExtensionSidebarView.height
        #expect(IconRowDrawer.reveal(shown: false, dragged: 0) == 0)
        #expect(IconRowDrawer.reveal(shown: false, dragged: -10) == 10)
        #expect(IconRowDrawer.reveal(shown: false, dragged: -500) == h)
        #expect(IconRowDrawer.reveal(shown: false, dragged: 40) == 0)
        #expect(IconRowDrawer.reveal(shown: true, dragged: 0) == h)
        #expect(IconRowDrawer.reveal(shown: true, dragged: 10) == h - 10)
    }

    @Test func letGoPastHalfwayOrFlickedAndTheRowSnaps() {
        let h = ExtensionSidebarView.height
        // Up from tucked away: past halfway, or a flick, opens it.
        #expect(IconRowDrawer.settle(shown: false, dragged: -(h / 2 + 1), predicted: -(h / 2 + 1)))
        #expect(!IconRowDrawer.settle(shown: false, dragged: -5, predicted: -5))
        #expect(IconRowDrawer.settle(shown: false, dragged: -5, predicted: -h))
        // Down from shown: the same, the other way.
        #expect(!IconRowDrawer.settle(shown: true, dragged: h / 2 + 1, predicted: h / 2 + 1))
        #expect(IconRowDrawer.settle(shown: true, dragged: 5, predicted: 5))
        #expect(!IconRowDrawer.settle(shown: true, dragged: 5, predicted: h))
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
