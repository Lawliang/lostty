#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct SidebarAutoHideTests {
    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test func startsHidden() {
        #expect(SidebarAutoHide().isVisible == false)
    }

    @Test func theEdgeRevealsIt() {
        var machine = SidebarAutoHide()
        machine.pointer(.edge, inside: true, now: t0)
        #expect(machine.isVisible)
    }

    @Test func leavingHidesAfterTheDelay() {
        var machine = SidebarAutoHide()
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.pointer(.sidebar, inside: false, now: t0)
        machine.tick(now: t0.addingTimeInterval(0.4))
        #expect(machine.isVisible)
        machine.tick(now: t0.addingTimeInterval(0.5))
        #expect(machine.isVisible == false)
    }

    @Test func movingFromTheEdgeIntoTheSidebarKeepsItShown() {
        var machine = SidebarAutoHide()
        machine.pointer(.edge, inside: true, now: t0)
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.pointer(.edge, inside: false, now: t0)
        #expect(machine.hideDeadline == nil)
        machine.tick(now: t0.addingTimeInterval(5))
        #expect(machine.isVisible)
    }

    @Test func comingBackCancelsTheHide() {
        var machine = SidebarAutoHide()
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.pointer(.sidebar, inside: false, now: t0)
        machine.pointer(.sidebar, inside: true, now: t0.addingTimeInterval(0.2))
        machine.tick(now: t0.addingTimeInterval(1))
        #expect(machine.isVisible)
    }

    @Test func neverHidesWhileAnAppIsOpen() {
        var machine = SidebarAutoHide()
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.appChanged(open: true, now: t0)
        machine.pointer(.sidebar, inside: false, now: t0)
        machine.tick(now: t0.addingTimeInterval(60))
        #expect(machine.isVisible)
    }

    @Test func closingAnAppWithThePointerAwayStartsTheHide() {
        var machine = SidebarAutoHide()
        machine.appChanged(open: true, now: t0)
        machine.appChanged(open: false, now: t0)
        machine.tick(now: t0.addingTimeInterval(0.5))
        #expect(machine.isVisible == false)
    }

    @Test func closingAnAppWithThePointerOnTheSidebarKeepsIt() {
        var machine = SidebarAutoHide()
        machine.pointer(.sidebar, inside: true, now: t0)
        machine.appChanged(open: true, now: t0)
        machine.appChanged(open: false, now: t0)
        machine.tick(now: t0.addingTimeInterval(5))
        #expect(machine.isVisible)
    }

    @MainActor
    @Test func theDriverHidesWhenItsTimerFires() {
        var clock = t0
        var pending: [@MainActor () -> Void] = []
        let driver = SidebarAutoHideDriver(now: { clock }, schedule: { _, work in pending.append(work) })
        driver.pointer(.edge, inside: true)
        driver.pointer(.edge, inside: false)
        #expect(driver.isVisible)
        clock = t0.addingTimeInterval(0.5)
        pending.forEach { $0() }
        #expect(driver.isVisible == false)
    }

    @MainActor
    @Test func theDriverRearmsWhenItsTimerFiresEarly() {
        var clock = t0
        var pending: [@MainActor () -> Void] = []
        let driver = SidebarAutoHideDriver(now: { clock }, schedule: { _, work in pending.append(work) })
        driver.pointer(.edge, inside: true)
        driver.pointer(.edge, inside: false)
        #expect(pending.count == 1)
        clock = t0.addingTimeInterval(0.2)
        let early = pending
        pending = []
        early.forEach { $0() }
        #expect(driver.isVisible)
        #expect(pending.count == 1)
        clock = t0.addingTimeInterval(0.5)
        pending.forEach { $0() }
        #expect(driver.isVisible == false)
    }
}
#endif
