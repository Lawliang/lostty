#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct SidebarAutoHideTests {
    private let width: CGFloat = 64

    @Test func startsHidden() {
        #expect(SidebarAutoHide().isVisible == false)
    }

    @Test func clickingTheHandleOpensAndCloses() {
        var machine = SidebarAutoHide()
        machine.toggle()
        #expect(machine.isVisible)
        machine.toggle()
        #expect(machine.isVisible == false)
    }

    @Test func draggingLeftPastHalfwayOpens() {
        var machine = SidebarAutoHide()
        machine.dragEnded(predicted: -20, width: width)
        #expect(machine.isVisible == false)
        machine.dragEnded(predicted: -40, width: width)
        #expect(machine.isVisible)
    }

    @Test func draggingRightPastHalfwayCloses() {
        var machine = SidebarAutoHide()
        machine.toggle()
        machine.dragEnded(predicted: 20, width: width)
        #expect(machine.isVisible)
        machine.dragEnded(predicted: 40, width: width)
        #expect(machine.isVisible == false)
    }

    @Test func theStripFollowsTheDragWithinItsWidth() {
        #expect(SidebarAutoHide.offset(open: false, drag: nil, width: width) == width)
        #expect(SidebarAutoHide.offset(open: true, drag: nil, width: width) == 0)
        #expect(SidebarAutoHide.offset(open: false, drag: -24, width: width) == 40)
        #expect(SidebarAutoHide.offset(open: false, drag: -500, width: width) == 0)
        #expect(SidebarAutoHide.offset(open: false, drag: 30, width: width) == width)
        #expect(SidebarAutoHide.offset(open: true, drag: 10, width: width) == 10)
    }

    @Test func anOpenAppHoldsItOut() {
        var machine = SidebarAutoHide()
        machine.appChanged(open: true)
        #expect(machine.isVisible)
        machine.appChanged(open: false)
        #expect(machine.isVisible == false)
    }

    @Test func openedFromTheHandleItStaysAfterAnAppCloses() {
        var machine = SidebarAutoHide()
        machine.toggle()
        machine.appChanged(open: true)
        machine.appChanged(open: false)
        #expect(machine.isVisible)
    }

    @MainActor
    @Test func theDriverShowsTheStripWhileDragging() {
        let driver = SidebarAutoHideDriver()
        driver.dragChanged(-10)
        #expect(driver.isVisible)
        #expect(driver.offset(width: width) == width - 10)
        driver.dragEnded(predicted: -10, width: width)
        #expect(driver.isVisible == false)
        #expect(driver.offset(width: width) == width)
    }
}

struct NotificationPlacementTests {
    @Test func notificationsSitLeftOfAnOpenPanel() {
        #expect(NotificationPlacement.trailingInset(active: nil, autoHide: false, stripVisible: false) == 0)
        #expect(NotificationPlacement.trailingInset(active: .skins, autoHide: false, stripVisible: false) == 0)
        #expect(NotificationPlacement.trailingInset(active: .branches, autoHide: false, stripVisible: false) == 340)
    }

    @Test func andLeftOfTheStripWhileItSlidesOverTheTerminal() {
        let strip = ExtensionSidebarView.width
        #expect(NotificationPlacement.trailingInset(active: nil, autoHide: true, stripVisible: false) == 0)
        #expect(NotificationPlacement.trailingInset(active: nil, autoHide: true, stripVisible: true) == strip)
        #expect(NotificationPlacement.trailingInset(active: .branches, autoHide: true, stripVisible: true) == 340 + strip)
    }
}
#endif
